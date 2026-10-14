"""The legacy entrypoint only translates arguments; blueprint owns generation."""
from pathlib import Path
import os
import runpy
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / 'create_feature.py'


class CreateFeatureTest(unittest.TestCase):
    def forwarded(self, *arguments):
        main = Mock(return_value=0)
        with patch.dict(sys.modules, {'blueprint': SimpleNamespace(main=main)}), patch.object(sys, 'argv', [str(SCRIPT), *arguments]), patch.object(sys, 'path', list(sys.path)), self.assertRaises(SystemExit) as result:
            runpy.run_path(str(SCRIPT), run_name='__main__')
        self.assertEqual(result.exception.code, 0)
        return main.call_args.args[0]

    def test_default_translates_to_api_and_preserves_arguments(self):
        self.assertEqual(self.forwarded('/workspace/apps/demo', 'user_profile', '--dry-run'),
                         ['feature', '/workspace/apps/demo', 'user_profile', '--dry-run', '--kind', 'api'])

    def test_presentation_only_flag_translates_to_kind(self):
        self.assertEqual(self.forwarded('/workspace/apps/demo', 'welcome', '--presentation-only'),
                         ['feature', '/workspace/apps/demo', 'welcome', '--kind', 'presentation'])

    def test_explicit_local_kind_is_preserved(self):
        for options in (['--kind', 'local'], ['--kind=local']):
            with self.subTest(options=options):
                self.assertEqual(self.forwarded('/workspace/apps/demo', 'drafts', *options),
                                 ['feature', '/workspace/apps/demo', 'drafts', *options])

    def test_real_subprocess_dry_run_and_invalid_names_are_nonmutating(self):
        with tempfile.TemporaryDirectory(prefix='legacy feature 中文 ') as temporary:
            root = Path(temporary)
            app = root / 'apps/demo'
            app.mkdir(parents=True)
            (root / 'pubspec.yaml').write_text('name: demo_workspace\nworkspace:\n  - apps/demo\n', encoding='utf-8')
            (app / 'pubspec.yaml').write_text('name: demo\nresolution: workspace\n', encoding='utf-8')
            for name, options, expected in (
                ('user_profile', ['--dry-run'], 0),
                ('hello_panel', ['--presentation-only', '--dry-run'], 0),
                ('local_notes', ['--kind', 'local', '--dry-run'], 0),
                ('conflicting', ['--kind', 'local', '--presentation-only'], 2),
                ('../../../escaped', [], 2),
                ('enum', [], 2),
            ):
                with self.subTest(name=name):
                    result = subprocess.run([sys.executable, str(SCRIPT), str(app), name, *options], capture_output=True, text=True, encoding='utf-8', check=False)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    if name == 'local_notes':
                        self.assertIn('local:', result.stdout)
            self.assertFalse((app / 'lib').exists())
            self.assertFalse((root / 'packages').exists())

    def test_piped_cli_preserves_unicode_paths_with_legacy_console_encoding(self):
        with tempfile.TemporaryDirectory(prefix='feature pipes 中文 ') as temporary:
            # Windows may return an 8.3 temp path; the CLI resolves its inputs.
            root = Path(temporary).resolve()
            app = root / 'apps/demo'
            app.mkdir(parents=True)
            (root / 'pubspec.yaml').write_text('name: demo_workspace\nworkspace:\n  - apps/demo\n', encoding='utf-8')
            (app / 'pubspec.yaml').write_text('name: demo\nresolution: workspace\n', encoding='utf-8')
            environment = {**os.environ, 'PYTHONIOENCODING': 'cp1252'}
            entries = ([str(SCRIPT)], [str(SCRIPT.parents[1] / 'blueprint.py'), 'feature'])
            for entry in entries:
                with self.subTest(entry=entry):
                    command = [sys.executable, *entry, str(app), 'hello_panel', '--kind', 'presentation', '--dry-run']
                    result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding='utf-8', check=False)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(str(app), result.stdout)
                    self.assertIn('中文', result.stdout)
            self.assertFalse((app / 'lib').exists())
            target = app / 'lib/features/hello_panel'
            target.mkdir(parents=True)
            for entry in entries:
                with self.subTest(error_entry=entry):
                    command = [sys.executable, *entry, str(app), 'hello_panel', '--kind', 'presentation', '--dry-run']
                    result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding='utf-8', check=False)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(str(target), result.stderr)
                    self.assertIn('中文', result.stderr)


if __name__ == '__main__':
    unittest.main()
