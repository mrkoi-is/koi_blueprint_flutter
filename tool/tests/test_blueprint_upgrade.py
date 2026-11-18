import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
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
        (self.root / 'blueprint.json').write_text(json.dumps(metadata), encoding='utf-8')

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

    def test_plan_cli_does_not_create_bytecode_in_reviewed_workspace(self):
        repository = Path(__file__).resolve().parents[2]
        shutil.copy2(repository / 'blueprint.py', self.root / 'blueprint.py')
        shutil.copytree(repository / 'tool', self.root / 'tool',
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        old = (self.root / 'blueprint.py').read_bytes()
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text())
        metadata['managedFiles']['blueprint.py'].update(
            sha256=digest(old), sourceSha256=digest(old))
        metadata_path.write_text(json.dumps(metadata))
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        (self.root / '.fvmrc').write_text('{"flutter":"3.47.2"}')
        (self.root / 'pubspec.yaml').write_text('name: demo\nworkspace:\n  - apps/demo_app\n')
        app = self.root / 'apps/demo_app'
        app.mkdir(parents=True)
        (app / 'pubspec.yaml').write_text('name: demo_app\nresolution: workspace\n')
        snapshot = lambda: {p.relative_to(self.root).as_posix(): p.read_bytes()
                            for p in self.root.rglob('*') if p.is_file()}
        before = snapshot()
        environment = dict(os.environ)
        environment.pop('PYTHONDONTWRITEBYTECODE', None)
        environment.pop('PYTHONPYCACHEPREFIX', None)
        result = subprocess.run([sys.executable, str(self.root / 'blueprint.py'),
                                 'upgrade', 'plan', '--app', str(app),
                                 '--source', str(self.source), '--output', str(self.source.parent / 'plan.json')],
                                cwd=self.root, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(snapshot()) - set(before), set(), 'Planning created files in the project')
        self.assertEqual(snapshot(), before)
        source_before = {p.relative_to(self.source).as_posix(): p.read_bytes()
                         for p in self.source.rglob('*') if p.is_file()}
        for output in (self.root / 'plan.json', self.source / 'tool/plan.json'):
            result = subprocess.run([sys.executable, str(self.root / 'blueprint.py'),
                                     'upgrade', 'plan', '--app', str(app),
                                     '--source', str(self.source), '--output', str(output)],
                                    cwd=self.root, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('outside the target and source workspaces', result.stderr)
            self.assertFalse(output.exists())
            self.assertEqual(snapshot(), before)
            self.assertEqual({p.relative_to(self.source).as_posix(): p.read_bytes()
                              for p in self.source.rglob('*') if p.is_file()}, source_before)

    @unittest.skipIf(os.name == 'nt', 'POSIX executable permissions')
    def test_new_tool_keeps_executable_mode_and_can_run_after_upgrade(self):
        script = self.source / 'tool/new-command'
        script.parent.mkdir()
        script.write_text('#!/bin/sh\nprintf "upgraded tool\\n"\n')
        script.chmod(0o755)
        result = upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        target = self.root / 'tool/new-command'
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)
        process = subprocess.run([str(target)], capture_output=True, text=True, check=True)
        self.assertEqual(process.stdout, 'upgraded tool\n')
        upgrade.rollback(self.root, result['transaction'])
        self.assertFalse(target.exists())

    @unittest.skipIf(os.name == 'nt', 'POSIX executable permissions')
    def test_existing_tool_keeps_user_permissions(self):
        target = self.root / 'blueprint.py'
        target.chmod(0o750)
        (self.source / 'blueprint.py').chmod(0o644)
        result = upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o750)
        upgrade.rollback(self.root, result['transaction'])
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o750)

    def test_backup_capture_rejects_concurrent_edit_before_journal(self):
        plan = upgrade.plan(self.root, self.source)
        original = upgrade._journal
        def changed(root, transaction):
            (self.root / 'blueprint.py').write_bytes(b'user edit during backup')
            return original(root, transaction)
        with patch.object(upgrade, '_journal', side_effect=changed):
            with self.assertRaisesRegex(ValueError, 'Concurrent modification'):
                upgrade.apply(self.root, plan)
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'user edit during backup')
        self.assertEqual(list((self.root / '.blueprint/upgrades').glob('*/journal.json')), [])

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
        metadata = json.loads((self.root / 'blueprint.json').read_text(encoding='utf-8'))
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
        metadata = json.loads((self.root / 'blueprint.json').read_text(encoding='utf-8'))
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

    def test_rollback_rechecks_backup_before_restoring(self):
        result = upgrade.apply(self.root, upgrade.plan(self.root, self.source))
        directory = self.root / '.blueprint/upgrades' / result['transaction']
        journal = json.loads((directory / 'journal.json').read_text())
        entry = next(item for item in journal['files'] if item['path'] == 'blueprint.py')
        backup = directory / entry['backup']
        original = upgrade._write_journal
        def change_backup(path, value):
            original(path, value)
            if value['state'] == 'rollback_incomplete':
                backup.write_bytes(b'backup changed after preflight')
        with patch.object(upgrade, '_write_journal', side_effect=change_backup):
            with self.assertRaisesRegex(ValueError, 'Backup corrupt'):
                upgrade.rollback(self.root, result['transaction'])
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'new cli')
        backup.write_bytes(b'old cli')
        upgrade.rollback(self.root, result['transaction'])
        self.assertEqual((self.root / 'blueprint.py').read_bytes(), b'old cli')

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
        source.write_bytes('# Demo — Agent 入口\n'.encode('utf-8'))
        self.assertEqual(source.read_bytes(), b'# Demo \xe2\x80\x94 Agent \xe5\x85\xa5\xe5\x8f\xa3\n')
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
        (self.root / 'pubspec.yaml').write_bytes(b'name: demo\n')
        (self.root / 'pubspec.lock').write_bytes(b'before\n')
        (self.root / '.fvmrc').write_bytes(b'{"flutter":"3.47.2"}')
        pub = self.root / 'packages/demo/pubspec.yaml'
        pub.parent.mkdir(parents=True)
        pub.write_bytes(b'name: demo_package\n')
        def run(argv, cwd, **kwargs):
            self.assertEqual(argv[1:], ['pub', 'get'])
            self.assertNotEqual(Path(cwd).resolve(), self.root.resolve())
            self.assertEqual((Path(cwd) / 'packages/demo/pubspec.yaml').read_bytes(), b'name: updated\n')
            (Path(cwd) / 'pubspec.lock').write_bytes(b'after\n')
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
            self.assertEqual((self.root / 'pubspec.lock').read_bytes(), b'before\n')
            pub.write_bytes(b'name: demo_package\ndependencies:\n  other:\n    path: /tmp/outside\n')
            with self.assertRaisesRegex(ValueError, 'External local path'):
                upgrade._resolve_dependencies(self.root.resolve(), {}, blueprint)

    def test_dependency_resolution_rejects_ambiguous_yaml_before_running_pub(self):
        import blueprint
        from types import SimpleNamespace
        (self.root / 'pubspec.lock').write_bytes(b'before\n')
        (self.root / '.fvmrc').write_bytes(b'{"flutter":"3.47.2"}')
        variants = [
            'dependencies:\n  other: {path: /tmp/outside}\n',
            'dependencies: {other: {path: /tmp/outside}}\n',
            '"dependencies":\n  other:\n    path: /tmp/outside\n',
            'dependencies:\n  other:\n    "path": /tmp/outside\n',
            'external: &outside {path: /tmp/outside}\ndependencies:\n  other: *outside\n',
            'dependencies:\n  other:\n    path: >-\n      /tmp/outside\n',
            'dependency_overrides:\n  other: {path: /tmp/outside}\n',
            'dependencies:\n  other:\n    path: ..\\outside\n',
            'dependencies:\n  other:\n    path: "packages/foo\\u002f..\\u002f..\\u002f.."\n',
        ]
        for value in variants:
            with self.subTest(value=value):
                (self.root / 'pubspec.yaml').write_text('name: demo\n' + value)
                with patch.object(blueprint, 'SDK', return_value=SimpleNamespace(flutter=Path('/sdk/flutter'))), \
                     patch.object(upgrade.subprocess, 'run') as command:
                    with self.assertRaisesRegex(ValueError, 'Ambiguous|External|block mapping'):
                        upgrade._resolve_dependencies(self.root.resolve(), {}, blueprint)
                    command.assert_not_called()

    def test_dependency_path_checks_allow_internal_blocks_and_reject_indented_root(self):
        import blueprint
        stage = self.root / 'isolated'
        stage.mkdir()
        text = ('name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n'
                '  local:\n    path: "../shared" # sibling within workspace\n'
                '  hosted_package:\n    hosted:\n      name: hosted_package\n'
                '      url: https://example.invalid\n    version: ^1.0.0\n'
                '  git_package:\n    git:\n      url: https://example.invalid/repo.git\n'
                '      path: packages/part\ndev_dependencies:\n  test: ^1.0.0\n')
        upgrade._check_dependency_paths(stage, 'packages/demo/pubspec.yaml', text, blueprint)
        with self.assertRaisesRegex(ValueError, 'Ambiguous dependency YAML'):
            upgrade._check_dependency_paths(stage, 'pubspec.yaml',
                ' name: demo\n dependencies:\n   other: {path: /tmp/outside}\n', blueprint)

    def test_package_baseline_and_new_rendered_app_test(self):
        old = b'old widget'
        package = self.root / 'packages/koi_ui/lib/widget.dart'
        package.parent.mkdir(parents=True)
        package.write_bytes(old)
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        metadata['managedFiles']['packages/koi_ui/lib/widget.dart'] = {
            'sha256': digest(old), 'sourceSha256': digest(old), 'source': 'packages/koi_ui/lib/widget.dart'}
        metadata_path.write_text(json.dumps(metadata), encoding='utf-8')
        package_source = self.source / 'packages/koi_ui/lib/widget.dart'
        package_source.parent.mkdir(parents=True)
        package_source.write_bytes(b'new widget')
        font = self.source / 'packages/koi_ui/test/golden/fonts/sample.ttf'
        font.parent.mkdir(parents=True)
        font.write_bytes(b'font-bytes')
        test = self.source / 'examples/starter_app/test/new_test.dart'
        test.parent.mkdir(parents=True)
        test.write_bytes(b'import "package:starter_app/main.dart"; StarterApp();')
        result = upgrade.plan(self.root, self.source)
        self.assertTrue(result['applicable'], result['conflicts'])
        upgrade.apply(self.root, result)
        self.assertEqual(package.read_bytes(), b'new widget')
        self.assertEqual((self.root / 'packages/koi_ui/test/golden/fonts/sample.ttf').read_bytes(), b'font-bytes')
        rendered = (self.root / 'apps/demo_app/test/new_test.dart').read_text(encoding='utf-8')
        self.assertIn('package:demo_app/main.dart', rendered)
        self.assertIn('DemoApp()', rendered)

    def test_new_app_lib_is_rendered_but_never_overwrites_unmanaged_file(self):
        origin = self.source / 'examples/starter_app/lib/feature/new_file.dart'
        origin.parent.mkdir(parents=True)
        origin.write_bytes(b'import "package:starter_app/main.dart"; StarterApp();')
        path = self.root / 'apps/demo_app/lib/feature/new_file.dart'
        def formatter(root, metadata, old, new, blueprint):
            return old, new + b' // formatted', {'sdk': 'fixture'}
        with patch.object(upgrade, '_format_app_pair', side_effect=formatter):
            result = upgrade.plan(self.root, self.source)
            self.assertTrue(result['applicable'], result['conflicts'])
            upgrade.apply(self.root, result)
            self.assertEqual(path.read_text(encoding='utf-8'), 'import "package:demo_app/main.dart"; DemoApp(); // formatted')
            self.assertEqual(json.loads((self.root / 'blueprint.json').read_text(encoding='utf-8'))['managedFiles']
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
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        metadata['managedFiles'][relative] = {'sha256': digest(generated), 'sourceSha256': digest(old), 'source': origin}
        metadata_path.write_text(json.dumps(metadata), encoding='utf-8')
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
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        metadata['managedFiles'][relative] = {'sha256': digest(old), 'sourceSha256': digest(old),
                                               'source': 'examples/starter_app/lib/main.dart'}
        metadata_path.write_text(json.dumps(metadata), encoding='utf-8')
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

    def test_changed_optional_package_requires_manual_migration(self):
        relative = 'packages/koi_diagnostics/lib/koi_diagnostics.dart'
        old, new = b'old diagnostics', b'new diagnostics'
        local, upstream = self.root / relative, self.source / relative
        local.parent.mkdir(parents=True)
        upstream.parent.mkdir(parents=True)
        local.write_bytes(old)
        upstream.write_bytes(new)
        (self.root / '.blueprint/baseline' / digest(old)).write_bytes(old)
        metadata_path = self.root / 'blueprint.json'
        metadata = json.loads(metadata_path.read_text())
        metadata['managedFiles'][relative] = {
            'sha256': digest(old), 'sourceSha256': digest(old), 'source': relative}
        metadata_path.write_text(json.dumps(metadata))
        plan = upgrade.plan(self.root, self.source)
        self.assertFalse(plan['applicable'])
        self.assertTrue(any(c['path'] == relative and c['reason'] == 'unsupported_managed_change'
                            for c in plan['conflicts']))
        with self.assertRaisesRegex(ValueError, 'Unresolved upgrade conflicts'):
            upgrade.apply(self.root, plan)
        self.assertEqual(local.read_bytes(), old)
        self.assertFalse((self.root / '.blueprint/upgrades').exists())

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
        metadata = json.loads((self.root / 'blueprint.json').read_text(encoding='utf-8'))
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
