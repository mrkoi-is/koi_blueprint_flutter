import hashlib
import json
from argparse import Namespace
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import blueprint
from tool.blueprint_capabilities import FileTransaction, install_plan, snapshot_install_inputs
from tool.blueprint_provenance import plan_install_baseline


def arb(locale, values):
    return json.dumps({'@@locale': locale, **values}, ensure_ascii=False).encode('utf-8')


class CapabilityArbMergeTest(unittest.TestCase):
    locales = ('en', 'zh', 'zh_Hant')

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.project = Path(temporary.name) / 'project'
        self.source = Path(temporary.name) / 'source'
        self.app = self.project / 'apps/demo'
        self.origins = {locale: f'examples/probe/{locale}.arb' for locale in self.locales}
        self.entry = {'id': 'probe', 'version': 1, 'platforms': ['web'], 'recipe': 'recipe',
                      'localizationSources': self.origins}
        self.catalog([self.entry])
        self.write(self.source / 'recipe/lib/probe.dart', b'const probe = 1;\n')
        self.write(self.project / 'pubspec.yaml', b'name: host\nworkspace:\n  - apps/demo\n')
        self.write(self.app / 'pubspec.yaml', b'name: demo\n')
        self.write(self.app / 'lib/core/capabilities/installed_capabilities.dart', b'// initial\n')
        self.metadata = self.project / 'blueprint.json'
        managed = {}
        for locale in self.locales:
            path = self.target(locale)
            original = arb(locale, {'title': 'Default', 'ready': 'Ready'})
            sha = hashlib.sha256(original).hexdigest()
            managed[path.relative_to(self.project).as_posix()] = {'sha256': sha, 'source': None}
            self.write(self.project / '.blueprint/baseline' / sha, original)
            self.write(path, arb(locale, {'title': '项目标题', 'ready': 'Ready', 'appOnly': '本地'}))
            self.recipe(locale, {'title': 'Default', 'ready': 'Start', 'count': '{n} items',
                                 '@count': {'description': 'Total', 'placeholders': {'n': {'type': 'int'}}}})
        self.write(self.metadata, json.dumps({'schema': 2, 'app': 'apps/demo', 'template': 'minimal',
                   'platforms': ['web'], 'capabilities': {}, 'managedFiles': managed}).encode())

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def catalog(self, entries):
        self.write(self.source / 'tool/capabilities/catalog.json',
                   json.dumps({'schema': 1, 'capabilities': entries}).encode())

    def target(self, locale):
        return self.app / f'lib/l10n/app_{locale}.arb'

    def recipe(self, locale, values):
        self.write(self.source / self.origins[locale], arb(locale, values))

    def plan(self, *selected):
        return install_plan(self.project, self.app, selected or ['probe'], self.source)

    def snapshot(self):
        return {p.relative_to(self.project): p.read_bytes() for p in self.project.rglob('*') if p.is_file()}

    def install(self, *selected):
        snapshot = snapshot_install_inputs(self.project, self.app)
        changes = self.plan(*selected)['changes']
        receipt = json.loads(changes['blueprint.json'])
        changes.update(plan_install_baseline(self.project, self.source, json.loads(self.metadata.read_bytes()),
                                             receipt, changes))
        changes['blueprint.json'] = json.dumps(receipt).encode()
        FileTransaction(self.project, changes, expected_hashes=snapshot).commit()
        return receipt

    def test_customized_app_merges_three_locales_without_adopting_user_values(self):
        before = self.snapshot()
        plan = self.plan()
        self.assertEqual(self.snapshot(), before)
        managed = json.loads(self.metadata.read_bytes())['managedFiles']
        receipt = self.install()
        self.assertEqual(receipt['managedFiles'][self.target('en').relative_to(self.project).as_posix()],
                         managed[self.target('en').relative_to(self.project).as_posix()])
        for locale in self.locales:
            path = self.target(locale)
            self.assertEqual(path.read_bytes(), plan['changes'][path.relative_to(self.project).as_posix()])
            self.assertEqual(json.loads(path.read_bytes()), {'@@locale': locale, 'title': '项目标题',
                'ready': 'Start', 'appOnly': '本地', 'count': '{n} items',
                '@count': {'description': 'Total', 'placeholders': {'n': {'type': 'int'}}}})
        self.assertEqual(self.plan()['changes'], {})

    def test_divergent_edits_and_deleted_required_key_report_path_and_key_atomically(self):
        path = self.target('zh_Hant')
        for key, value in [('title', 'Different'), ('ready', 'Ready'), ('appOnly', 'Recipe wording')]:
            with self.subTest(key=key):
                local = json.loads(path.read_bytes())
                local.pop('ready', None)
                path.write_bytes(arb('zh_Hant', local))
                self.recipe('zh_Hant', {key: value})
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, rf'app_zh_Hant\.arb.*{key}'):
                    self.plan()
                self.assertEqual(self.snapshot(), before)

    def test_same_version_refresh_uses_prior_recipe_and_preserves_reformatted_bytes_on_retry(self):
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        local['count'] = '{n} records'
        local['ready'] = 'Proceed'  # The incoming change already matches.
        path.write_bytes(arb('en', local))
        self.recipe('en', {'title': 'Default', 'count': '{n} items', 'ready': 'Proceed',
                           'added': 'Added', '@count': {'description': 'Updated', 'placeholders': {'n': {'type': 'int'}}}})
        self.install()
        merged = json.loads(path.read_bytes())
        self.assertEqual(merged['count'], '{n} records')
        self.assertEqual(merged['ready'], 'Proceed')
        self.assertEqual(merged['added'], 'Added')
        self.assertEqual(merged['@count']['description'], 'Updated')
        path.write_bytes(arb('en', merged))
        before = self.snapshot()
        self.assertEqual(self.plan()['changes'], {})
        self.assertEqual(self.snapshot(), before)
        self.recipe('en', {'count': '{n} entries'})
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*count'):
            self.plan()
        self.assertEqual(self.snapshot(), before)

    def test_invalid_or_missing_baseline_wrong_locale_and_duplicate_key_fail_readonly(self):
        path = self.target('en')
        original = path.read_bytes()
        relative = path.relative_to(self.project).as_posix()
        sha = json.loads(self.metadata.read_bytes())['managedFiles'][relative]['sha256']
        blob = self.project / '.blueprint/baseline' / sha
        trusted = blob.read_bytes()
        for old, local, diagnostic in ((None, original, 'baseline'), (b'corrupt', original, 'baseline'),
                                       (trusted, arb('zh', {}), 'locale'),
                                       (trusted, b'{"@@locale":"en","title":"one","title":"two"}', 'title')):
            with self.subTest(diagnostic=diagnostic):
                if old is None:
                    blob.unlink()
                else:
                    blob.write_bytes(old)
                path.write_bytes(local)
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, diagnostic):
                    self.plan()
                self.assertEqual(self.snapshot(), before)

    def test_historical_receipt_accepts_only_reference_bytes_matching_its_digest(self):
        receipt = self.install()
        saved = receipt['capabilities']['probe']['localizations']['en']
        blob = self.project / '.blueprint/baseline' / saved['sourceSha256']
        reference = self.project / '.blueprint/reference' / saved['source']
        old_recipe = blob.read_bytes()
        blob.unlink()  # Historical installers only saved the digest.
        self.write(reference, arb('en', {'count': 'Wrong historical value'}))
        self.recipe('en', {'ready': 'New action', 'extra': 'Extra'})
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'Missing verified ARB baseline'):
            self.plan()
        self.assertEqual(self.snapshot(), before)
        reference.write_bytes(old_recipe)
        self.install()
        data = json.loads(self.target('en').read_bytes())
        self.assertEqual((data['ready'], data['extra'], data['count']), ('New action', 'Extra', '{n} items'))

    def test_same_metadata_key_diverges_and_identical_edits_converge_without_rewriting_app(self):
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        local['@count']['description'] = 'Edited by project'
        custom = arb('en', local)
        path.write_bytes(custom)
        self.recipe('en', {'@count': {'description': 'Edited in recipe'}})
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*@count'):
            self.plan()
        self.assertEqual(self.snapshot(), before)
        self.recipe('en', {'@count': local['@count']})
        plan = self.plan()
        self.assertNotIn(path.relative_to(self.project).as_posix(), plan['changes'])
        self.install()
        self.assertEqual(path.read_bytes(), custom)
        self.assertEqual(self.plan()['changes'], {})

    def test_metadata_compares_json_value_types_inside_placeholders(self):
        def metadata(example):
            return {'placeholders': {'n': {'example': example}}}
        self.recipe('en', {'@count': metadata(1)})
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        local['@count'] = metadata(True)
        path.write_bytes(arb('en', local))
        self.recipe('en', {'@count': metadata(2)})
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*@count'):
            self.plan()

    def test_separate_install_cannot_overwrite_another_installed_recipes_key(self):
        # Start with clean App baselines so the installed ARB itself becomes the next baseline.
        managed = json.loads(self.metadata.read_bytes())['managedFiles']
        for relative, entry in managed.items():
            (self.project / relative).write_bytes((self.project / '.blueprint/baseline' / entry['sha256']).read_bytes())
        self.install()
        self.catalog([self.entry, {'id': 'more', 'version': 1, 'platforms': ['web'],
                     'providedByTemplate': True, 'localizationSources': {'en': 'more.arb'}}])
        self.write(self.source / 'more.arb', arb('en', {'count': 'Different meaning'}))
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*count'):
            self.plan('more')
        self.assertEqual(self.snapshot(), before)

    def test_shared_recipe_key_preserves_project_override_for_either_install_order(self):
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        local['count'] = '{n} records'
        path.write_bytes(arb('en', local))
        self.catalog([self.entry, {'id': 'more', 'version': 1, 'platforms': ['web'],
                     'providedByTemplate': True, 'localizationSources': {'en': 'more.arb'}}])
        self.write(self.source / 'more.arb', arb('en', {'count': '{n} items', 'newKey': 'New'}))
        for selected in (('more',), ('more', 'probe'), ('probe', 'more')):
            with self.subTest(selected=selected):
                plan = self.plan(*selected)
                merged = json.loads(plan['changes'][path.relative_to(self.project).as_posix()])
                self.assertEqual((merged['count'], merged['newKey']), ('{n} records', 'New'))
        # A matching local override cannot make incompatible recipe owners agree.
        self.write(self.source / 'more.arb', arb('en', {'count': '{n} records'}))
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*count'):
            self.plan('more')

    def test_separate_install_reports_deleted_shared_key_even_on_a_customized_app(self):
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        del local['count']
        path.write_bytes(arb('en', local))
        self.catalog([self.entry, {'id': 'more', 'version': 1, 'platforms': ['web'],
                     'providedByTemplate': True, 'localizationSources': {'en': 'more.arb'}}])
        self.write(self.source / 'more.arb', arb('en', {'count': '{n} items'}))
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, r'removed locally.*app_en\.arb.*count'):
            self.plan('more')
        self.assertEqual(self.snapshot(), before)

    def test_dropped_recipe_locale_releases_claims_but_preserves_app_bytes(self):
        self.install()
        original = self.target('en').read_bytes()
        del self.origins['en']
        self.catalog([self.entry])
        receipt = self.install()
        self.assertEqual(set(receipt['capabilities']['probe']['localizations']), {'zh', 'zh_Hant'})
        self.assertEqual(self.target('en').read_bytes(), original)
        self.assertEqual(self.plan()['changes'], {})

    def test_refresh_does_not_adopt_edits_to_an_unrelated_installed_capability(self):
        self.catalog([self.entry, {'id': 'other', 'version': 1, 'platforms': ['web'], 'recipe': 'other'}])
        self.write(self.source / 'other/lib/other.dart', b'const original = true;\n')
        first = self.install('probe', 'other')
        unrelated = self.app / 'lib/other.dart'
        unrelated.write_bytes(b'const projectEdit = true;\n')
        self.recipe('en', {'added': 'New'})
        self.write(self.project / 'pubspec.lock', b'# fixture\n')
        args = Namespace(app=str(self.app), action='add', id='probe', config=None, dry_run=False)
        with patch.object(blueprint, 'ROOT', self.source), patch.object(blueprint, 'SDK'), \
                patch.object(blueprint, 'run'), patch.object(blueprint, 'members', return_value=[]), \
                patch.object(blueprint, 'check_localizations'), redirect_stdout(StringIO()):
            blueprint.capability(args)
        receipt = json.loads(self.metadata.read_bytes())
        self.assertEqual(receipt['capabilities']['other'], first['capabilities']['other'])
        self.assertEqual(unrelated.read_bytes(), b'const projectEdit = true;\n')
        with self.assertRaisesRegex(ValueError, 'other.dart'):
            self.plan('other')

    def test_recipe_merge_keeps_the_source_digest_of_the_installed_app_template(self):
        path = self.target('en')
        relative = path.relative_to(self.project).as_posix()
        metadata = json.loads(self.metadata.read_bytes())
        entry = metadata['managedFiles'][relative]
        old_sha = entry['sha256']
        path.write_bytes((self.project / '.blueprint/baseline' / old_sha).read_bytes())
        entry.update(source='examples/starter_app/lib/l10n/app_en.arb', sourceSha256=old_sha)
        self.write(self.source / entry['source'], arb('en', {'title': 'Uninstalled template update'}))
        self.metadata.write_text(json.dumps(metadata))
        receipt = self.install()
        applied = receipt['managedFiles'][relative]
        self.assertNotEqual(applied['sha256'], old_sha)
        self.assertEqual(applied['sourceSha256'], old_sha)

    def test_concurrent_edit_to_a_converged_locale_blocks_the_new_receipt(self):
        self.install()
        path = self.target('en')
        local = json.loads(path.read_bytes())
        local['ready'] = 'New'
        path.write_bytes(arb('en', local))
        self.recipe('en', {'ready': 'New'})
        self.write(self.project / 'pubspec.lock', b'# fixture\n')
        before = self.snapshot()

        def edit_while_staging(*args, **kwargs):
            path.write_bytes(arb('en', {**local, 'ready': 'Concurrent user edit'}))

        args = Namespace(app=str(self.app), action='add', id='probe', config=None, dry_run=False)
        with patch.object(blueprint, 'ROOT', self.source), patch.object(blueprint, 'SDK'), \
                patch.object(blueprint, 'run', side_effect=edit_while_staging), \
                patch.object(blueprint, 'members', return_value=[]), patch.object(blueprint, 'check_localizations'), \
                redirect_stdout(StringIO()), self.assertRaisesRegex(ValueError, 'changed while planning.*app_en.arb'):
            blueprint.capability(args)
        before[path.relative_to(self.project)] = arb('en', {**local, 'ready': 'Concurrent user edit'})
        self.assertEqual(self.snapshot(), before)

    def test_multiple_planned_recipes_and_concurrent_edit(self):
        self.catalog([self.entry, {'id': 'more', 'version': 1, 'platforms': ['web'],
                     'providedByTemplate': True, 'dependencies': ['probe'],
                     'localizationSources': {'en': 'more.arb'}}])
        incoming = self.source / 'more.arb'
        self.write(incoming, arb('en', {'count': '{n} items', 'more': 'More'}))
        prev = snapshot_install_inputs(self.project, self.app)
        plan = self.plan('more')
        path = self.target('en')
        data = json.loads(plan['changes'][path.relative_to(self.project).as_posix()])
        self.assertEqual((data['count'], data['more']), ('{n} items', 'More'))
        self.write(incoming, arb('en', {'title': 'Competing recipe'}))
        with self.assertRaisesRegex(ValueError, r'app_en\.arb.*title'):
            self.plan('more')
        before = self.snapshot()
        transaction = FileTransaction(self.project, plan['changes'], expected_hashes=prev)
        def failed_refresh():
            raise OSError('refresh failed')
        with self.assertRaisesRegex(OSError, 'refresh failed'):
            transaction.commit(failed_refresh)
        self.assertEqual(self.snapshot(), before)
        path.write_bytes(b'concurrent edit')
        with self.assertRaisesRegex(ValueError, 'changed while planning'):
            FileTransaction(self.project, plan['changes'], expected_hashes=prev)
        self.assertEqual(path.read_bytes(), b'concurrent edit')
