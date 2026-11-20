import json
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import blueprint


class WorkspaceGenerationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='blueprint codegen ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.tool = self.root / '.dart_tool'
        self.tool.mkdir()
        self.sdk = SimpleNamespace(flutter='flutter', dart='dart')
        self.paths = {'app': self.root / 'apps/host', 'bridge': self.root / 'modules/bridge',
                      'runtime': self.root / 'packages/基础 #1', 'builder': self.root / 'tools/my builder'}
        self.graph = {
            'app': (['bridge'], ['build_runner', 'builder']),
            'bridge': (['adapter'], []),
            'adapter': (['adapter_support', 'runtime'], []),
            'adapter_support': (['adapter'], []),
            'runtime': ([], ['build_runner']),
            'builder': (['runtime'], ['build_runner']),
            'build_runner': ([], []),
        }
        for name, path in self.paths.items():
            path.mkdir(parents=True)
            (path / 'pubspec.yaml').write_text(f'name: {name}\n# build_runner: see workspace tooling\n')
        (self.paths['app'] / 'l10n.yaml').touch()
        self.write_resolution()
        self.enterContext(patch.object(blueprint, 'SDK', return_value=self.sdk))
        self.enterContext(patch.object(blueprint, 'members', return_value=list(self.paths.values())))

    def write_resolution(self):
        config = []
        for name, path in self.paths.items():
            uri = path.as_uri() if name == 'builder' else '../' + path.as_uri()[len(self.root.as_uri()) + 1:]
            config.append({'name': name, 'rootUri': uri})
        graph = [{'name': name, 'dependencies': deps, 'devDependencies': dev}
                 for name, (deps, dev) in self.graph.items()]
        (self.tool / 'package_config.json').write_text(json.dumps({'packages': config}))
        (self.tool / 'package_graph.json').write_text(json.dumps({'packages': graph}))

    def test_generate_commands_and_validate_run_dependencies_first(self):
        real_check = blueprint.check
        for phase in ('generate', 'generate-check', 'validate'):
            with self.subTest(phase=phase), patch.object(blueprint, 'run') as run:
                args = SimpleNamespace(workspace=str(self.root), phase=phase, coverage_min=80)
                if phase == 'validate':
                    def check_generation_only(step):
                        if step.phase == 'generate-check':
                            real_check(step)
                    with patch.object(blueprint, 'validation_prerequisites'), \
                            patch.object(blueprint, 'check', side_effect=check_generation_only):
                        blueprint.validate(args)
                else:
                    real_check(args)
                calls = [call.args for call in run.call_args_list]
                build = ['dart', 'run', 'build_runner', 'build']
                self.assertEqual([cwd for command, cwd in calls if command == build],
                                 [self.paths[n] for n in ('runtime', 'builder', 'app')])
                self.assertLess(calls.index((['flutter', 'gen-l10n'], self.paths['app'])),
                                calls.index((build, self.paths['app'])))

    def test_invalid_resolution_stops_before_any_generator_runs(self):
        def check_failure(expected):
            with patch.object(blueprint, 'run') as run, self.assertRaisesRegex(ValueError, expected):
                blueprint.check(SimpleNamespace(workspace=self.root, phase='generate-check'))
            run.assert_not_called()

        self.graph['runtime'][0].append('app')
        self.write_resolution()
        check_failure('cycle.*app')
        self.graph['runtime'][0].clear()
        del self.graph['runtime']
        self.write_resolution()
        check_failure('runtime')
        (self.tool / 'package_graph.json').write_text('{')
        check_failure('package_graph.json')
        (self.tool / 'package_config.json').unlink()
        check_failure('package_config.json')

    def test_unresolved_member_and_ambiguous_config_are_rejected(self):
        config = self.tool / 'package_config.json'
        data = json.loads(config.read_bytes())
        app = data['packages'].pop(0)
        config.write_text(json.dumps(data))
        with patch.object(blueprint, 'run') as run, self.assertRaisesRegex(ValueError, 'host'):
            blueprint.check(SimpleNamespace(workspace=self.root, phase='generate-check'))
        run.assert_not_called()
        data['packages'].extend([app, {**app, 'name': 'alias'}])
        config.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'host'):
            blueprint.check(SimpleNamespace(workspace=self.root, phase='generate-check'))

    def test_absolute_package_uri_through_checkout_symlink_matches_member(self):
        from tool.blueprint_codegen import generation_plan
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary) / 'checkout'
            try:
                checkout.symlink_to(self.root, target_is_directory=True)
            except OSError as error:
                self.skipTest(f'Directory symlinks unavailable: {error}')
            config = self.tool / 'package_config.json'
            data = json.loads(config.read_bytes())
            data['packages'][0]['rootUri'] = (checkout / 'apps/host').as_uri()
            config.write_text(json.dumps(data))
            plan = generation_plan(self.root, list(self.paths.values()))
            self.assertEqual([path for path, build in plan if build],
                             [self.paths[n] for n in ('runtime', 'builder', 'app')])


class CapabilityGenerationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name).resolve()
        self.root, self.source = base / 'project', base / 'source'
        self.app = self.root / 'apps/host'
        hook = self.app / 'lib/core/capabilities/installed_capabilities.dart'
        hook.parent.mkdir(parents=True)
        hook.write_text('// initial\n')
        (self.app / 'pubspec.yaml').write_text('name: consumer\nresolution: workspace\n')
        (self.root / 'pubspec.yaml').write_text('name: project\nworkspace:\n  - apps/host\n')
        (self.root / 'pubspec.lock').write_text('# fixture\n')
        (self.root / 'blueprint.json').write_text(json.dumps({'schema': 2, 'app': 'apps/host',
            'template': 'minimal', 'platforms': ['web'], 'capabilities': {}, 'managedFiles': {}}))
        catalog = self.source / 'tool/capabilities/catalog.json'
        catalog.parent.mkdir(parents=True)
        catalog.write_text(json.dumps({'schema': 1, 'capabilities': [{'id': 'probe', 'version': 1,
            'platforms': ['web'], 'providedByTemplate': True, 'packages': ['new_core']}]}))
        package = self.source / 'packages/new_core'
        package.mkdir(parents=True)
        (package / 'pubspec.yaml').write_text('name: new_core\nresolution: workspace\n')
        self.runs = []
        self.cycle_in_project = False
        self.enterContext(patch.object(blueprint, 'ROOT', self.source))
        self.enterContext(patch.object(blueprint, 'SDK', return_value=SimpleNamespace(flutter='flutter', dart='dart')))
        self.enterContext(patch.object(blueprint, 'run', side_effect=self.fake_sdk))
        self.enterContext(redirect_stdout(StringIO()))

    def fake_sdk(self, command, cwd, capture=False):
        if command[1:3] == ['pub', 'get']:
            self.assertIn('  - packages/new_core', (cwd / 'pubspec.yaml').read_text())
            self.assertIn('  new_core: any', (cwd / 'apps/host/pubspec.yaml').read_text())
            tool = cwd / '.dart_tool'
            tool.mkdir(exist_ok=True)
            config = [{'name': 'consumer', 'rootUri': (cwd / 'apps/host').as_uri()},
                      {'name': 'new_core', 'rootUri': (cwd / 'packages/new_core').as_uri()}]
            graph = [{'name': 'consumer', 'dependencies': ['new_core'], 'devDependencies': ['build_runner']},
                     {'name': 'new_core', 'dependencies': ['consumer'] if self.cycle_in_project and cwd == self.root
                      else [], 'devDependencies': ['build_runner']}, {'name': 'build_runner', 'dependencies': []}]
            (tool / 'package_config.json').write_text(json.dumps({'packages': config}))
            (tool / 'package_graph.json').write_text(json.dumps({'packages': graph}))
        elif command[1:4] == ['pub', 'workspace', 'list']:
            return json.dumps({'packages': [{'name': name, 'path': path} for name, path in
                [('project', '.'), ('consumer', 'apps/host'), ('new_core', 'packages/new_core')]]})
        elif command[1:] == ['run', 'build_runner', 'build']:
            owner = cwd.parents[1]
            part = owner / 'packages/new_core/new_core.g.dart'
            if cwd.name == 'new_core':
                cache = cwd / '.dart_tool/build'
                cache.mkdir(parents=True, exist_ok=True)
                (cache / 'asset_graph.json').write_text(json.dumps({'workspace': str(owner)}))
                part.write_text('// generated in this workspace\n')
            else:
                self.assertTrue(part.is_file(), 'Consumer started before its dependency generated here')
            self.runs.append((owner, cwd.name))

    def install(self):
        blueprint.capability(SimpleNamespace(action='add', app=str(self.app), id='probe', config=None, dry_run=False))

    def test_new_package_generates_before_app_in_stage_and_live_workspace(self):
        self.install()
        stage = self.runs[0][0]
        self.assertNotEqual(stage, self.root)
        self.assertEqual(self.runs, [(stage, 'new_core'), (stage, 'host'), (self.root, 'new_core'), (self.root, 'host')])
        self.assertTrue((self.root / 'packages/new_core/new_core.g.dart').is_file())
        self.install()
        self.assertEqual(len(self.runs), 4)

    def test_broken_live_graph_rolls_back_install_after_successful_staging(self):
        self.cycle_in_project = True
        tracked = [self.root / 'blueprint.json', self.root / 'pubspec.yaml', self.root / 'pubspec.lock',
                   self.app / 'pubspec.yaml', self.app / 'lib/core/capabilities/installed_capabilities.dart']
        before = {p: p.read_bytes() for p in tracked}
        with self.assertRaisesRegex(ValueError, 'cycle'):
            self.install()
        self.assertEqual([name for _, name in self.runs], ['new_core', 'host'])
        self.assertTrue(all(owner != self.root for owner, _ in self.runs))
        self.assertEqual(before, {p: p.read_bytes() for p in tracked})
        self.assertFalse((self.root / 'packages/new_core/pubspec.yaml').exists())

    def fail_live_app(self, before_failure=None):
        def run(command, cwd, capture=False):
            if cwd == self.app and command[1:] == ['run', 'build_runner', 'build']:
                if before_failure:
                    before_failure()
                raise ValueError('App generator failed')
            return self.fake_sdk(command, cwd, capture)
        with patch.object(blueprint, 'run', side_effect=run), self.assertRaisesRegex(ValueError, 'App generator failed'):
            self.install()

    def test_live_app_failure_after_dependency_generation_allows_retry(self):
        self.fail_live_app()
        self.assertFalse((self.root / 'packages/new_core').exists())
        self.assertNotIn('probe', json.loads((self.root / 'blueprint.json').read_bytes())['capabilities'])
        self.install()
        self.assertEqual(self.runs[-2:], [(self.root, 'new_core'), (self.root, 'host')])

    def test_rollback_preserves_user_edits_in_new_support_package(self):
        package = self.root / 'packages/new_core'
        part = package / 'new_core.g.dart'
        note = package / 'notes.txt'
        def edit():
            part.write_text('// edited while the generator was running\n')
            note.write_text('draft')
            (package / '.dart_tool/user-note').write_text('keep me')
        self.fail_live_app(edit)
        self.assertEqual(part.read_text(), '// edited while the generator was running\n')
        self.assertEqual(note.read_text(), 'draft')
        self.assertEqual((package / '.dart_tool/user-note').read_text(), 'keep me')
        with self.assertRaisesRegex(ValueError, 'Unregistered support package'):
            self.install()
