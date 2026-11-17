import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tool.native_runtime_watchdog import _group_exists


SCRIPT = Path(__file__).resolve().parents[1] / 'native_runtime_watchdog.py'


@unittest.skipUnless(os.name == 'posix', 'POSIX process groups required')
class NativeRuntimeWatchdogTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='koi-watchdog-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / 'native-runtime.log'
        self.report = self.root / 'report.json'

    def invoke(self, program, timeout='5', grace='.2', reporter=False):
        evidence = (['--events', 'events.jsonl', '--target', 'integration_test/smoke.dart']
                    if reporter else [])
        return subprocess.run(
            [sys.executable, str(SCRIPT), '--timeout', timeout, '--grace', grace,
             '--log', str(self.log), '--report', str(self.report), *evidence, '--',
             sys.executable, '-c', program],
            cwd=self.root, capture_output=True, text=True, timeout=12,
        )

    def test_success_streams_output_and_records_success(self):
        process = self.invoke("print('runtime ready', flush=True)")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn('runtime ready', process.stdout)
        self.assertIn('runtime ready', self.log.read_text())
        report = json.loads(self.report.read_text())
        self.assertTrue(report['passed'])
        self.assertFalse(report['timedOut'])
        self.assertEqual(report['exitCode'], 0)

    def test_nonzero_stays_failure_and_existing_log_is_not_overwritten(self):
        process = self.invoke("import sys; print('failure', flush=True); sys.exit(7)")
        self.assertEqual(process.returncode, 7)
        self.assertFalse(json.loads(self.report.read_text())['passed'])
        original = self.log.read_bytes()
        self.assertEqual(self.invoke("print('should not run')").returncode, 2)
        self.assertEqual(self.log.read_bytes(), original)

    def test_timeout_kills_owned_process_group_and_keeps_partial_output(self):
        child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('grandchild ready',flush=True); time.sleep(60)"
        program = ("import signal,subprocess,sys,time; "
                   "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                   f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); "
                   "print('grandchild_pid='+str(p.pid),flush=True); time.sleep(60)")
        process = self.invoke(program, timeout='1', grace='.3')
        self.assertEqual(process.returncode, 124, process.stderr)
        log = self.log.read_text()
        self.assertIn('grandchild_pid=', log)
        self.assertIn('grandchild ready', log)
        self.assertIn('KOI_WATCHDOG timeout', log)
        report = json.loads(self.report.read_text())
        self.assertTrue(report['timedOut'])
        self.assertFalse(report['passed'])
        child_pid = next(line.split('=', 1)[1] for line in log.splitlines() if line.startswith('grandchild_pid='))
        result = subprocess.run(['ps', '-o', 'stat=', '-p', child_pid], capture_output=True, text=True)
        # A reparented zombie is already dead; only a running descendant is a leak.
        self.assertTrue(not result.stdout.strip() or result.stdout.strip().startswith('Z'), result.stdout)

    def test_darwin_permission_error_only_accepts_proven_dead_groups(self):
        for listing, gone in (('123 Z\n456 S\n', True), ('456 S\n', True),
                              ('123 S\n', False), ('unparseable\n', False)):
            with self.subTest(listing=listing), patch('tool.native_runtime_watchdog.sys.platform', 'darwin'), patch('tool.native_runtime_watchdog.os.killpg', side_effect=PermissionError()), patch('tool.native_runtime_watchdog.subprocess.run', return_value=SimpleNamespace(stdout=listing)):
                if gone:
                    self.assertFalse(_group_exists(123))
                else:
                    with self.assertRaises(PermissionError):
                        _group_exists(123)

    def test_cancel_signal_kills_owned_group_and_records_failure(self):
        process = subprocess.Popen(
            [sys.executable, str(SCRIPT), '--timeout', '30', '--grace', '.2',
             '--log', str(self.log), '--report', str(self.report), '--', sys.executable,
             '-c', "import time; print('runtime ready',flush=True); time.sleep(60)"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        def cleanup():
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.log.exists() and 'runtime ready' in self.log.read_text():
                break
            time.sleep(.05)
        else:
            self.fail('runtime did not start')
        process.terminate()
        _stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 2, stderr)
        state = json.loads(self.report.read_text())
        self.assertEqual(state['cleanup'], 'interrupted')
        self.assertFalse(state['passed'])
        self.assertIn('runtime ready', self.log.read_text())

    def test_zero_exit_with_truncated_reporter_is_rejected(self):
        process = self.invoke("from pathlib import Path; Path('events.jsonl').write_text('')", reporter=True)
        self.assertEqual(process.returncode, 2, process.stderr)
        result = json.loads(self.report.read_text())
        self.assertFalse(result['passed'])
        self.assertFalse(result['evidence']['evidenceComplete'])

    def test_complete_reporter_proves_exactly_one_executed_test(self):
        events = [
            {'type': 'start', 'protocolVersion': '0.1.1'},
            {'type': 'suite', 'suite': {'id': 0, 'path': 'integration_test/smoke.dart'}},
            {'type': 'allSuites', 'count': 1},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'native smoke'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': False, 'hidden': False},
            {'type': 'done', 'success': True},
        ]
        payload = ''.join(json.dumps(item) + '\n' for item in events)
        process = self.invoke(f"from pathlib import Path; Path('events.jsonl').write_text({payload!r})", reporter=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        result = json.loads(self.report.read_text())
        self.assertTrue(result['passed'])
        self.assertEqual(result['evidence']['executed'], 1)

    def test_skipped_reporter_case_is_not_success(self):
        events = [
            {'type': 'start', 'protocolVersion': '0.1.1'},
            {'type': 'suite', 'suite': {'id': 0, 'path': 'integration_test/smoke.dart'}},
            {'type': 'allSuites', 'count': 1},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'native smoke'}},
            {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': True, 'hidden': False},
            {'type': 'done', 'success': True},
        ]
        payload = ''.join(json.dumps(item) + '\n' for item in events)
        process = self.invoke(f"from pathlib import Path; Path('events.jsonl').write_text({payload!r})", reporter=True)
        self.assertEqual(process.returncode, 2, process.stderr)
        self.assertFalse(json.loads(self.report.read_text())['passed'])


if __name__ == '__main__':
    unittest.main()
