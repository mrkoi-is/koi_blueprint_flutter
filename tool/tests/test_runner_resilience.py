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

    def execute(self, argv, cwd, output, timeout, stdout_name='events.jsonl'):
        target = str(self.member / 'test/example_test.dart')
        events = [
            {'type': 'start', 'protocolVersion': '0.1.1'},
            {'type': 'suite', 'suite': {'id': 0, 'path': target}},
            {'type': 'allSuites', 'count': 1},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'case'}},
            {'type': 'testDone', 'testID': 1, 'hidden': False, 'skipped': False, 'result': 'success'},
            {'type': 'done', 'success': True},
        ]
        payload = '\n'.join(json.dumps(x) for x in events)
        if '--file-reporter' in argv:
            report = argv[argv.index('--file-reporter') + 1]
            Path(report.removeprefix('json:')).write_text(payload)
            (output / stdout_name).write_text('[BROWSER CONSOLE] [log]: Starting suite\n')
        else:
            (output / stdout_name).write_text(payload)
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

    def test_chrome_console_is_preserved_separately_from_case_evidence(self):
        self.args.platform = 'chrome'
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.execute', side_effect=self.execute):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual((result['status'], result['executed']), ('passed', 1))
        artifacts = result['artifacts']
        self.assertIn('[BROWSER CONSOLE]', Path(artifacts['browser-console.log']['path']).read_text())
        events = Path(artifacts['events.jsonl']['path'])
        self.assertEqual(json.loads(events.read_text().splitlines()[-1])['type'], 'done')
        self.assertNotIn(f'json:{events}', result['replay']['argv'])

    def test_chrome_requires_file_report_even_when_stdout_contains_valid_events(self):
        self.args.platform = 'chrome'
        def missing_report(argv, cwd, output, timeout, stdout_name):
            return self.execute([], cwd, output, timeout, stdout_name)
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.execute', side_effect=missing_report):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertFalse(result['evidenceComplete'])
        self.assertNotEqual(result['status'], 'passed')

    def test_run_emits_portable_member_and_target_paths(self):
        self.member = self.root / 'apps/demo_app'
        target = self.member / 'test/browser/example_test.dart'
        target.parent.mkdir(parents=True)
        target.touch()
        self.args.member = 'apps/demo_app'
        self.args.path = ['test/browser/example_test.dart']
        def execute(argv, cwd, output, timeout, stdout_name):
            events = [
                {'type': 'start', 'protocolVersion': '0.1.1'},
                {'type': 'suite', 'suite': {'id': 0, 'path': str(target)}},
                {'type': 'allSuites', 'count': 1},
                {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'case'}},
                {'type': 'testDone', 'testID': 1, 'hidden': False, 'skipped': False, 'result': 'success'},
                {'type': 'done', 'success': True},
            ]
            (output / 'events.jsonl').write_text('\n'.join(json.dumps(x) for x in events), encoding='utf-8')
            (output / 'stderr.log').write_text('', encoding='utf-8')
            return {'exitCode': 0, 'timedOut': False, 'interrupted': False,
                    'cleanup': 'not_needed', 'launchError': None, 'durationSeconds': 1}
        with patch('tool.blueprint_test.source_manifest', return_value=self.manifest), \
             patch('tool.blueprint_test.execute', side_effect=execute):
            result = self.run_fake(self.root, self.sdk, [self.member], self.args)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['member'], 'apps/demo_app')
        self.assertEqual(result['requiredTargets'], ['test/browser/example_test.dart'])
        self.assertEqual(result['replay']['member'], 'apps/demo_app')
        self.assertEqual(result['replay']['paths'], ['test/browser/example_test.dart'])

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
