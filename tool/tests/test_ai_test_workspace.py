import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess

from tool.ai_test_workspace import inspect_workspace, platforms_for_host
from tool.ai_test_ci import run_suite


class WorkspaceKindTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()

    def test_source_must_have_both_examples(self):
        with self.assertRaisesRegex(ValueError, 'missing'):
            inspect_workspace(self.root)
        for name in ('ui_lab', 'workbench_app'):
            (self.root / 'examples' / name).mkdir(parents=True)
        self.assertEqual(inspect_workspace(self.root), ('source', None))

    def test_generated_metadata_and_suite_restrictions(self):
        app = self.root / 'apps/custom_app'
        app.mkdir(parents=True)
        metadata = self.root / 'blueprint.json'
        metadata.write_text(json.dumps({'schema': 2, 'template': 'minimal', 'app': 'apps/custom_app'}))
        self.assertEqual(inspect_workspace(self.root), ('minimal', 'apps/custom_app'))
        with self.assertRaisesRegex(ValueError, 'only available'):
            run_suite(self.root, 'app')
        with self.assertRaisesRegex(ValueError, 'unavailable'):
            run_suite(self.root, 'workbench')
        metadata.write_text(json.dumps({'schema': 2, 'template': 'workbench', 'app': 'apps/custom_app'}))
        self.assertEqual(inspect_workspace(self.root), ('workbench', 'apps/custom_app'))

    def test_invalid_metadata_cannot_fall_back_to_source(self):
        for value in ({'schema': 1, 'template': 'workbench', 'app': 'apps/x'},
                      {'schema': 2, 'template': 'workbench', 'app': '../outside'},
                      {'schema': 2, 'template': 'minimal', 'app': 'apps/x\nkind=source'}):
            (self.root / 'blueprint.json').write_text(json.dumps(value))
            with self.subTest(value=value), self.assertRaises(ValueError):
                inspect_workspace(self.root)

    def test_workbench_suite_resolves_the_generated_member(self):
        (self.root / 'apps/custom_app').mkdir(parents=True)
        (self.root / 'blueprint.json').write_text(json.dumps(
            {'schema': 2, 'template': 'workbench', 'app': 'apps/custom_app'}))
        result = subprocess.CompletedProcess([], 2, '', '')
        with patch('tool.ai_test_ci.subprocess.run', return_value=result) as run:
            index, passed = run_suite(self.root, 'workbench')
        self.assertFalse(passed)
        self.assertEqual(run.call_count, 4)
        self.assertTrue(all(call.args[0][call.args[0].index('--member') + 1] == 'apps/custom_app'
                            for call in run.call_args_list))
        self.assertEqual(json.loads(index.read_text())['member'], 'apps/custom_app')

    def test_platforms_follow_project_selection_and_reject_invalid_metadata(self):
        (self.root / 'apps/custom_app').mkdir(parents=True)
        metadata = self.root / 'blueprint.json'
        data = {'schema': 2, 'template': 'workbench', 'app': 'apps/custom_app',
                'platforms': ['web', 'macos', 'windows']}
        metadata.write_text(json.dumps(data))
        self.assertEqual(platforms_for_host(self.root, 'Linux'), ['web'])
        self.assertEqual(platforms_for_host(self.root, 'macOS'), ['macos'])
        self.assertEqual(platforms_for_host(self.root, 'Windows'), ['windows'])
        data['platforms'] = ['web', 'web']
        metadata.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'platform'):
            platforms_for_host(self.root, 'Linux')


if __name__ == '__main__':
    unittest.main()
