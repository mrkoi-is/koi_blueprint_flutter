import hashlib
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

from tool import blueprint_upgrade as upgrade


def digest(value):
    return hashlib.sha256(value).hexdigest()


class UpgradeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root, self.source = base / 'project', base / 'source'
        self.root.mkdir()
        self.source.mkdir()
        (self.source / 'blueprint.py').write_bytes(b'new cli')
        old = b'old cli'
        (self.root / 'blueprint.py').write_bytes(old)
        (self.root / '.blueprint/baseline').mkdir(parents=True)
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        metadata = {'schema': 2, 'name': 'demo', 'app': 'apps/demo_app', 'template': 'minimal',
                    'platforms': ['web'], 'source': {'sourceSha256': 'a' * 64},
                    'managedFiles': {'blueprint.py': {'sha256': digest(old),
                        'sourceSha256': digest(old), 'source': 'blueprint.py'}}, 'capabilities': {}}
        (self.root / 'blueprint.json').write_text(json.dumps(metadata))

    def test_plan_is_readonly_and_apply_rollback_restores_bytes(self):
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        plan = upgrade.plan(self.root, self.source)
        self.assertTrue(plan['applicable'])
        self.assertEqual(before, {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()})
        result = upgrade.apply(self.root, plan)
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'new cli')
        self.assertEqual(upgrade.rollback(self.root, result['transaction'])['state'], 'rolled_back')
        for name, content in before.items():
            self.assertEqual((self.root / name).read_bytes(), content)

    def test_custom_conflict_and_reviewed_resolution(self):
        (self.root / 'blueprint.py').write_bytes(b'my cli')
        plan = upgrade.plan(self.root, self.source)
        self.assertFalse(plan['applicable'])
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            upgrade.apply(self.root, plan)
        resolution = {'blueprint.py': {'choice': 'merged', 'currentSha256': digest(b'my cli')}}
        plan = upgrade.plan(self.root, self.source, resolution)
        self.assertTrue(plan['applicable'])
        upgrade.apply(self.root, plan)
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'my cli')
        metadata = json.loads((self.root / 'blueprint.json').read_text())
        self.assertEqual(metadata['managedFiles']['blueprint.py']['sha256'], digest(b'new cli'))

    def test_dirty_source_identity_is_not_reported_clean(self):
        def git(*args):
            subprocess.run(['git', *args], cwd=self.source, check=True, capture_output=True)
        git('init')
        git('add', 'blueprint.py')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
        (self.source / 'blueprint.py').write_bytes(b'new dirty cli')
        result = upgrade.plan(self.root, self.source)
        self.assertTrue(result['sourceIdentity']['dirty'])
        self.assertIsNotNone(result['sourceIdentity']['commit'])
        upgrade.apply(self.root, result)
        metadata = json.loads((self.root / 'blueprint.json').read_text())
        self.assertTrue(metadata['source']['dirty'])

    def test_stale_or_tampered_plan_rejected(self):
        plan = upgrade.plan(self.root, self.source)
        (self.root / 'blueprint.py').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'stale'):
            upgrade.apply(self.root, plan)
        (self.root / 'blueprint.py').write_bytes(b'old cli')
        plan['operations'][0]['content'] = 'eA=='
        with self.assertRaisesRegex(ValueError, 'integrity'):
            upgrade.apply(self.root, plan)

    def test_rollback_refuses_later_edit(self):
        result = upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        (self.root / 'blueprint.py').write_bytes(b'later edit')
        with self.assertRaisesRegex(ValueError, 'Rollback conflict'):
            upgrade.rollback(self.root, result['transaction'])
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'later edit')

    def test_interrupted_apply_is_recoverable(self):
        original = upgrade.atomic_write
        def fail(path, content):
            if path.resolve() == (self.root / 'blueprint.py').resolve():
                raise OSError('simulated crash')
            return original(path, content)
        with patch.object(upgrade, 'atomic_write', side_effect=fail):
            with self.assertRaisesRegex(OSError, 'simulated'):
                upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        transaction = next((self.root / '.blueprint/upgrades').iterdir()).name
        with self.assertRaisesRegex(ValueError, 'Incomplete transaction'):
            upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        upgrade.rollback(self.root, transaction)
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'old cli')

    def test_untracked_identical_guidance_requires_review(self):
        source = self.source / 'AGENTS.md'
        source.write_text('# Demo — Agent 入口\n')
        (self.root / 'AGENTS.md').write_bytes(source.read_bytes())
        result = upgrade.plan(self.root, self.source)
        self.assertTrue(any(item['path'] == 'AGENTS.md' and item['reason'] == 'no_baseline'
                            for item in result['conflicts']))

    def test_supported_dependency_insertions_preserve_custom_yaml(self):
        old = b'dev_dependencies:\n  flutter_test:\n    sdk: flutter\nflutter:\n  generate: true\n'
        target = b'dev_dependencies:\n  flutter_driver:\n    sdk: flutter\n  flutter_test:\n    sdk: flutter\nflutter:\n  generate: true\n  uses-material-design: true\n'
        local = b'dev_dependencies:\n  # local package\n  custom: ^2.0.0\n  flutter_test:\n    sdk: flutter\nflutter:\n  generate: true\n'
        merged, additions = upgrade._merge_supported_pubspec(old, local, target)
        self.assertEqual(additions, ['material', 'driver'])
        self.assertIn(b'# local package\n  custom: ^2.0.0', merged)
        self.assertIn(b'  flutter_driver:\n    sdk: flutter\n', merged)
        self.assertIn(b'  uses-material-design: true\n', merged)
        with self.assertRaisesRegex(ValueError, 'conflicting local'):
            upgrade._merge_supported_pubspec(old, local + b'  uses-material-design: false\n', target)
        with self.assertRaisesRegex(ValueError, 'unsupported upstream'):
            upgrade._merge_supported_pubspec(old, local, target.replace(b'generate: true', b'generate: false'))

    def test_dependency_resolution_is_isolated_and_rejects_escaping_paths(self):
        import blueprint
        from types import SimpleNamespace
        (self.root / 'pubspec.yaml').write_text('name: demo\n')
        (self.root / 'pubspec.lock').write_text('before\n')
        (self.root / '.fvmrc').write_text('{"flutter":"3.47.2"}')
        pub = self.root / 'packages/demo/pubspec.yaml'
        pub.parent.mkdir(parents=True)
        pub.write_text('name: demo_package\n')
        def run(argv, cwd, **kwargs):
            self.assertEqual(argv[1:], ['pub', 'get'])
            self.assertNotEqual(Path(cwd).resolve(), self.root.resolve())
            self.assertEqual((Path(cwd) / 'packages/demo/pubspec.yaml').read_text(), 'name: updated\n')
            (Path(cwd) / 'pubspec.lock').write_text('after\n')
            return SimpleNamespace(returncode=0, stderr='')
        with patch.object(blueprint, 'SDK', return_value=SimpleNamespace(flutter=Path('/sdk/flutter'))), \
             patch.object(blueprint, 'pinned_flutter_version', return_value='3.47.2'), \
             patch.object(upgrade.subprocess, 'run', side_effect=run):
            lock, inputs, diff, resolver = upgrade._resolve_dependencies(
                self.root.resolve(), {'packages/demo/pubspec.yaml': b'name: updated\n'}, blueprint)
            self.assertEqual(lock, b'after\n')
            self.assertIn('-before', diff)
            self.assertEqual(resolver['command'], ['flutter', 'pub', 'get'])
            self.assertEqual(inputs['pubspec.lock'], digest(b'before\n'))
            self.assertEqual((self.root / 'pubspec.lock').read_text(), 'before\n')
            pub.write_text('name: demo_package\ndependencies:\n  other:\n    path: /tmp/outside\n')
            with self.assertRaisesRegex(ValueError, 'External local path'):
                upgrade._resolve_dependencies(self.root.resolve(), {}, blueprint)

    def test_package_baseline_and_new_rendered_app_test(self):
        old = b'old widget'
        package = self.root / 'packages/koi_ui/lib/widget.dart'
        package.parent.mkdir(parents=True)
        package.write_bytes(old)
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text())
        metadata['managedFiles']['packages/koi_ui/lib/widget.dart'] = {
            'sha256': digest(old), 'sourceSha256': digest(old), 'source': 'packages/koi_ui/lib/widget.dart'}
        metadata_path.write_text(json.dumps(metadata))
        package_source = self.source / 'packages/koi_ui/lib/widget.dart'
        package_source.parent.mkdir(parents=True)
        package_source.write_bytes(b'new widget')
        font = self.source / 'packages/koi_ui/test/golden/fonts/sample.ttf'
        font.parent.mkdir(parents=True)
        font.write_bytes(b'font-bytes')
        test = self.source / 'examples/starter_app/test/new_test.dart'
        test.parent.mkdir(parents=True)
        test.write_text('import "package:starter_app/main.dart"; StarterApp();')
        result = upgrade.plan(self.root, self.source)
        self.assertTrue(result['applicable'], result['conflicts'])
        upgrade.apply(self.root, result)
        self.assertEqual(package.read_bytes(), b'new widget')
        self.assertEqual((self.root / 'packages/koi_ui/test/golden/fonts/sample.ttf').read_bytes(), b'font-bytes')
        rendered = (self.root / 'apps/demo_app/test/new_test.dart').read_text()
        self.assertIn('package:demo_app/main.dart', rendered)
        self.assertIn('DemoApp()', rendered)

    def test_new_app_lib_is_rendered_but_never_overwrites_unmanaged_file(self):
        origin = self.source / 'examples/starter_app/lib/feature/new_file.dart'
        origin.parent.mkdir(parents=True)
        origin.write_text('import "package:starter_app/main.dart"; StarterApp();')
        path = self.root / 'apps/demo_app/lib/feature/new_file.dart'
        def formatter(root, metadata, old, new, blueprint):
            return old, new + b' // formatted', {'sdk': 'fixture'}
        with patch.object(upgrade, '_format_app_pair', side_effect=formatter):
            result = upgrade.plan(self.root, self.source)
            self.assertTrue(result['applicable'], result['conflicts'])
            upgrade.apply(self.root, result)
            self.assertEqual(path.read_text(), 'import "package:demo_app/main.dart"; DemoApp(); // formatted')
            self.assertEqual(json.loads((self.root / 'blueprint.json').read_text())['managedFiles']
                             ['apps/demo_app/lib/feature/new_file.dart']['source'],
                             'examples/starter_app/lib/feature/new_file.dart')

    def test_existing_unmanaged_lib_even_identical_is_a_conflict(self):
        origin = self.source / 'examples/starter_app/lib/new.dart'
        origin.parent.mkdir(parents=True)
        origin.write_bytes(b'ordinary content')
        path = self.root / 'apps/demo_app/lib/new.dart'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'ordinary content')
        with patch.object(upgrade, '_format_app_pair', side_effect=lambda r, m, old, new, b: (old, new, {})):
            result = upgrade.plan(self.root, self.source)
        self.assertTrue(any(c['path'] == 'apps/demo_app/lib/new.dart' and c['reason'] == 'no_baseline'
                            for c in result['conflicts']))
        self.assertEqual(path.read_bytes(), b'ordinary content')

    def test_app_dart_upgrade_requires_reproducible_baseline_and_local_edits_conflict(self):
        origin = 'examples/starter_app/lib/main.dart'
        relative = 'apps/demo_app/lib/main.dart'
        old = b'import "package:starter_app/app.dart";\n'
        generated = b'import "package:demo_app/app.dart";\n'
        newer = b'import "package:starter_app/new.dart";\n'
        path = self.root / relative
        path.parent.mkdir(parents=True)
        path.write_bytes(generated)
        (self.root / '.blueprint/baseline' / digest(generated)).write_bytes(generated)
        ref = self.root / '.blueprint/reference' / origin
        ref.parent.mkdir(parents=True)
        ref.write_bytes(old)
        upstream = self.source / origin
        upstream.parent.mkdir(parents=True)
        upstream.write_bytes(newer)
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text())
        metadata['managedFiles'][relative] = {'sha256': digest(generated), 'sourceSha256': digest(old), 'source': origin}
        metadata_path.write_text(json.dumps(metadata))
        fake_formatter = lambda root, meta, old, new, blueprint: (old, new, {'sdk': 'fixture'})
        with patch.object(upgrade, '_format_app_pair', side_effect=fake_formatter):
            # Reference replacement remains an independent explicit review.
            reviewed = {'.blueprint/reference/' + origin: {'choice': 'take-upstream',
                         'currentSha256': digest(old), 'targetSha256': digest(newer)}}
            result = upgrade.plan(self.root, self.source, reviewed)
            self.assertTrue(result['applicable'], result['conflicts'])
            operation = next(o for o in result['operations'] if o['path'] == relative)
            self.assertEqual(operation['after'], digest(b'import "package:demo_app/new.dart";\n'))
            path.write_bytes(b'local edit')
            conflict = upgrade.plan(self.root, self.source, reviewed)
            self.assertTrue(any(c['path'] == relative and c['reason'] == 'conflict' for c in conflict['conflicts']))
        with patch.object(upgrade, '_format_app_pair', return_value=(b'wrong', b'new', {})):
            blocked = upgrade.plan(self.root, self.source, reviewed)
            self.assertTrue(any(c['path'] == relative and c['reason'] == 'unsupported_managed_change' for c in blocked['conflicts']))

    def test_existing_project_reports_app_and_reference_blockers(self):
        old = b'old app'
        relative = 'apps/demo_app/lib/main.dart'
        (self.root / relative).parent.mkdir(parents=True)
        (self.root / relative).write_bytes(old)
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text())
        metadata['managedFiles'][relative] = {'sha256': digest(old), 'sourceSha256': digest(old),
                                               'source': 'examples/starter_app/lib/main.dart'}
        metadata_path.write_text(json.dumps(metadata))
        origin = self.source / 'examples/starter_app/lib/main.dart'
        origin.parent.mkdir(parents=True)
        origin.write_bytes(b'new app')
        reference = self.root / '.blueprint/reference/examples/starter_app/lib/main.dart'
        reference.parent.mkdir(parents=True)
        reference.write_bytes(old)
        result = upgrade.plan(self.root, self.source)
        reasons = [entry['reason'] for entry in result['conflicts']]
        self.assertEqual(reasons.count('unsupported_managed_change'), 1)
        self.assertEqual(reasons.count('unmanaged_reference'), 1)
        self.assertFalse(result['applicable'])

    def test_reference_review_records_real_new_baseline(self):
        origin = self.source / 'examples/starter_app/README.md'
        origin.parent.mkdir(parents=True)
        origin.write_bytes(b'new reference')
        relative = '.blueprint/reference/examples/starter_app/README.md'
        local = self.root / relative
        local.parent.mkdir(parents=True)
        local.write_bytes(b'old custom')
        result = upgrade.plan(self.root, self.source)
        conflict = next(c for c in result['conflicts'] if c['path'] == relative)
        self.assertEqual(conflict['reason'], 'unmanaged_reference')
        resolution = {relative: {'choice': 'take-upstream', 'currentSha256': digest(b'old custom'),
                                 'targetSha256': digest(b'new reference')}}
        reviewed = upgrade.plan(self.root, self.source, resolution)
        self.assertTrue(reviewed['applicable'], reviewed['conflicts'])
        upgrade.apply(self.root, reviewed)
        metadata = json.loads((self.root / 'blueprint.json').read_text())
        self.assertEqual(metadata['referenceFiles'][relative], digest(b'new reference'))
        self.assertEqual((self.root / '.blueprint/baseline' / digest(b'new reference')).read_bytes(), b'new reference')
        origin.write_bytes(b'newer reference')
        second = upgrade.plan(self.root, self.source)
        self.assertTrue(second['applicable'], second['conflicts'])
        upgrade.apply(self.root, second)
        self.assertEqual(local.read_bytes(), b'newer reference')
        local.write_bytes(b'local edits')
        origin.write_bytes(b'upstream edits')
        conflict = upgrade.plan(self.root, self.source)
        self.assertTrue(any(c['reason'] == 'reference_conflict' for c in conflict['conflicts']))

    def test_untrusted_baseline_and_reference_block(self):
        (self.root / '.blueprint/baseline' / digest(b'old cli')).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'corrupt baseline'):
            upgrade.plan(self.root, self.source)
        (self.root / '.blueprint/baseline' / digest(b'old cli')).write_bytes(b'old cli')
        ref = Path('examples/starter_app/lib/main.dart')
        (self.source / ref).parent.mkdir(parents=True)
        (self.source / ref).write_bytes(b'new example')
        local = self.root / '.blueprint/reference' / ref
        local.parent.mkdir(parents=True)
        local.write_bytes(b'custom example')
        result = upgrade.plan(self.root, self.source)
        self.assertFalse(result['applicable'])
        self.assertTrue(any(c['reason'] == 'unmanaged_reference' for c in result['conflicts']))


if __name__ == '__main__':
    unittest.main()
