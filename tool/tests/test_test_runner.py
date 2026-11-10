import json
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

from tool.blueprint_test import execute, select_targets, summarize


class TestEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.target = self.root / 'test/example_test.dart'
        self.target.parent.mkdir()
        self.target.touch()
        self.log = self.root / 'events.jsonl'
        self.events = [
            {'type': 'start', 'protocolVersion': '0.1.1'},
            {'type': 'suite', 'suite': {'id': 0, 'path': str(self.target)}},
            {'type': 'allSuites', 'count': 1},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'loading'}},
            {'type': 'testDone', 'testID': 1, 'hidden': True, 'skipped': False, 'result': 'success'},
            {'type': 'testStart', 'test': {'id': 2, 'suiteID': 0, 'name': 'rename persists'}},
            {'type': 'testDone', 'testID': 2, 'hidden': False, 'skipped': False, 'result': 'success'},
            {'type': 'done', 'success': True},
        ]

    def result(self, code=0, targets=None):
        self.log.write_text('\n'.join(json.dumps(x) for x in self.events), encoding='utf-8')
        return summarize(self.log, code, targets or [self.target], self.root)

    def test_complete_pass_excludes_loader(self):
        result = self.result()
        self.assertEqual((result['status'], result['executed']), ('passed', 1))
        self.assertTrue(result['evidenceComplete'])
        self.assertTrue(result['scopeComplete'])

    def test_zero_exit_cannot_override_failure(self):
        self.events[-2]['result'] = 'failure'
        self.assertEqual(self.result()['status'], 'failed')

    def test_nonzero_and_compilation_errors_never_pass(self):
        self.assertEqual(self.result(1)['status'], 'error')
        self.events.insert(-1, {'type': 'error', 'error': 'Compilation failed', 'stackTrace': 'source:1'})
        self.assertEqual(self.result()['status'], 'error')

    def test_truncated_or_duplicate_end_cannot_pass(self):
        end = self.events.pop()
        self.assertEqual(self.result()['status'], 'inconclusive')
        self.events += [end, end]
        self.assertEqual(self.result()['status'], 'inconclusive')

    def test_incomplete_test_cannot_pass(self):
        del self.events[-2]
        self.assertEqual(self.result()['status'], 'inconclusive')

    def test_only_loading_or_skipped_tests_are_not_run(self):
        self.events = self.events[:5] + self.events[-1:]
        self.assertEqual(self.result()['status'], 'not_run')
        self.assertEqual(self.result(79)['status'], 'not_run')
        self.assertEqual(self.result(1)['status'], 'error')

    def test_required_skip_with_other_pass_is_inconclusive(self):
        self.events[-1:-1] = [
            {'type': 'testStart', 'test': {'id': 3, 'suiteID': 0, 'name': 'required'}},
            {'type': 'testDone', 'testID': 3, 'hidden': False, 'skipped': True, 'result': 'success'},
        ]
        self.assertEqual(self.result()['status'], 'inconclusive')
        self.assertEqual(self.result()['skipped'], ['required'])

    def test_missing_requested_file_cannot_pass(self):
        missing = self.root / 'test/downstream_test.dart'
        result = self.result(targets=[self.target, missing])
        self.assertEqual(result['status'], 'inconclusive')
        self.assertEqual(result['missingTargets'], [str(missing)])

    def test_malformed_summary_and_unknown_protocol_cannot_pass(self):
        self.result()
        with self.log.open('a') as stream:
            stream.write('\nAll tests passed!\n')
        self.assertEqual(summarize(self.log, 0, [self.target], self.root)['status'], 'inconclusive')
        self.events[0]['protocolVersion'] = 'future'
        self.assertEqual(self.result()['status'], 'inconclusive')
        self.assertEqual(self.result(None)['status'], 'inconclusive')

    def test_active_member_and_explicit_files_only(self):
        self.assertEqual(select_targets(self.root.parent, self.root.name,
                                       ['test/example_test.dart'], [self.root]),
                         (self.root, [self.target]))
        for paths in (['../outside_test.dart'], ['test'],
                      ['test/example_test.dart', 'test/example_test.dart']):
            with self.assertRaises(ValueError):
                select_targets(self.root.parent, self.root.name, paths, [self.root])
        with self.assertRaises(ValueError):
            select_targets(self.root.parent, self.root.name, ['test/example_test.dart'], [])

    def test_fresh_streams_do_not_reuse_previous_success(self):
        self.result()
        process = execute([sys.executable, '-c', 'print("truncated")'], self.root, self.root, 5)
        self.assertEqual(process['exitCode'], 0)
        self.assertEqual(self.log.read_text().strip(), 'truncated')
        self.assertEqual(summarize(self.log, 0, [self.target], self.root)['status'], 'inconclusive')

    def test_deadline_and_launch_failure_are_recorded(self):
        process = execute([sys.executable, '-c', 'import time; time.sleep(30)'], self.root, self.root, .1)
        self.assertTrue(process['timedOut'])
        self.assertIn(process['cleanup'], ('terminated', 'already_exited'))
        self.assertEqual(summarize(self.log, process['exitCode'], [self.target], self.root,
                                   timed_out=True)['status'], 'timeout')
        failed = execute([str(self.root / 'nonexistent')], self.root, self.root, 1)
        self.assertIsNotNone(failed['launchError'])

    @unittest.skipIf(os.name == 'nt', 'POSIX process-group assertion; Windows uses taskkill /T')
    def test_timeout_kills_owned_descendant(self):
        pid_path = self.root / 'child.pid'
        code = ('import subprocess,sys,time,pathlib; '
                'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]); '
                f'pathlib.Path({str(pid_path)!r}).write_text(str(child.pid)); time.sleep(30)')
        process = execute([sys.executable, '-c', code], self.root, self.root, 1)
        self.assertTrue(process['timedOut'])
        self.assertEqual(process['cleanup'], 'terminated')
        pid = int(pid_path.read_text())
        # A zombie is already terminated, awaiting the host's reaper.
        probe = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True)
        self.assertTrue(probe.returncode != 0 or probe.stdout.strip().startswith('Z'), probe.stdout)


if __name__ == '__main__':
    unittest.main()
