import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from tool.blueprint_test import run_tests


class RunnerResilienceTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.member = self.root / 'member'
        (self.member / 'test').mkdir(parents=True)
        (self.member / 'test/example_test.dart').touch()
        (self.root / '.fvmrc').write_text('{"flutter":"3.47.2"}')
        self.sdk = SimpleNamespace(flutter='flutter')
        self.args = SimpleNamespace(member='member', path=['test/example_test.dart'],
                                    timeout=30, platform='vm', name=None)
        self.manifest = {'baseline_commit': 'abc', 'source_sha256': 'before'}

    def run_fake(self, root, sdk, workspace, args):
        return run_tests(root, sdk, workspace, args)

    def execute(self, argv, cwd, output, timeout):
        target = str(self.member / 'test/example_test.dart')
        events = [
            {'type': 'start', 'protocolVersion': '0.1.1'},
            {'type': 'suite', 'suite': {'id': 0, 'path': target}},
            {'type': 'allSuites', 'count': 1},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'case'}},
            {'type': 'testDone', 'testID': 1, 'hidden': False, 'skipped': False, 'result': 'success'},
            {'type': 'done', 'success': True},
        ]
        (output / 'events.jsonl').write_text('\n'.join(json.dumps(x) for x in events))
        (output / 'stderr.log').write_text('')
        return {'exitCode': 0, 'timedOut': False, 'interrupted': False,
                'cleanup': 'not_needed', 'launchError': None, 'durationSeconds': 1}

    def test_source_mutation_is_inconclusive_and_result_published(self):
        modified = {**self.manifest, 'source_sha256': 'after'}
        with patch('tool.blueprint_test.source_manifest', side_effect=[self.manifest, modified]), \
             patch('tool.blueprint_test.execute', side_effect=self.execute):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual(result['status'], 'inconclusive')
        self.assertFalse(result['evidenceComplete'])
        self.assertTrue(result['source']['changedDuringRun'])
        self.assertEqual(json.loads(Path(result['resultPath']).read_text()), result)
        self.assertFalse(Path(result['resultPath']).with_name('.result.json.tmp').exists())

    def test_failure_to_collect_golden_is_error_with_result(self):
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.golden_files', side_effect=[{}, OSError('disk error')]), \
             patch('tool.blueprint_test.execute', side_effect=self.execute):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual(result['status'], 'error')
        self.assertFalse(result['evidenceComplete'])
        self.assertEqual(result['diagnostics'][0]['phase'], 'golden_collect')
        self.assertTrue(Path(result['resultPath']).exists())

    def test_failed_cleanup_cannot_pass_even_with_passing_events(self):
        def cleanup_failed(*args):
            return {**self.execute(*args), 'cleanup': 'failed'}
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.execute', side_effect=cleanup_failed):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual(result['status'], 'error')
        self.assertFalse(result['evidenceComplete'])
        self.assertEqual(result['diagnostics'][0]['kind'], 'cleanup_failed')

    def test_launch_failure_is_recorded(self):
        def launch_failed(*args):
            return {**self.execute(*args), 'launchError': 'not found'}
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.execute', side_effect=launch_failed):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['diagnostics'][0]['kind'], 'launch_failed')


if __name__ == '__main__':
    unittest.main()
