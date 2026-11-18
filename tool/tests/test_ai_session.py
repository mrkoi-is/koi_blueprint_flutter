import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from tool import ai_session
from tool.ai_session import flutter_app_id, owned_processes


TOOL = Path(__file__).resolve().parents[1] / 'ai_session.py'


@unittest.skipUnless(os.name == 'posix', 'POSIX sessions required')
class AiSessionTest(unittest.TestCase):
    def test_failure_cleanup_does_not_signal_a_reused_observed_pid(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], process_group=0)
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        sid = os.getsid(unrelated.pid)
        state = {'observed': {str(unrelated.pid): {'sessionId': sid, 'started': 'previous process'}}}
        try:
            with patch.object(ai_session, 'processes', return_value={unrelated.pid: (os.getpid(), sid, 'new process')}):
                self.assertEqual(ai_session.cleanup_failed_session(child, state), [])
            self.assertIsNotNone(child.returncode)
            self.assertIsNone(unrelated.poll())
        finally:
            for process in (child, unrelated):
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)

    def test_supervisor_failures_reap_owned_tree_and_preserve_unrelated_process(self):
        for failure in ('monitor', 'journal'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                ready, descendant_ready = root / 'ready', root / 'descendant-ready'
                descendant_code = (
                    'import signal,time; from pathlib import Path; '
                    'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                    f'Path({str(descendant_ready)!r}).touch(); time.sleep(60)')
                code = (
                    'import signal,subprocess,sys,time; from pathlib import Path\n'
                    'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                    f'child=subprocess.Popen([sys.executable,"-c",{descendant_code!r}])\n'
                    f'while not Path({str(descendant_ready)!r}).exists(): time.sleep(.01)\n'
                    f'Path({str(ready)!r}).write_text(str(child.pid))\n'
                    'time.sleep(60)')
                unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
                children = []
                original_popen, original_publish = subprocess.Popen, ai_session.publish
                def launch(*args, **kwargs):
                    child = original_popen(*args, **kwargs)
                    children.append(child)
                    deadline = time.monotonic() + 5
                    while not ready.exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue(ready.exists(), 'fixture child did not start')
                    return child
                def publish(path, state):
                    if failure == 'journal' and state['status'] == 'running':
                        raise OSError('journal unavailable')
                    original_publish(path, state)
                try:
                    with patch.object(ai_session.subprocess, 'Popen', side_effect=launch), \
                            patch.object(ai_session, 'processes', side_effect=PermissionError('ps unavailable')), \
                            patch.object(ai_session, 'publish', side_effect=publish):
                        result = ai_session.supervise(root, root, [sys.executable, '-c', code], 'a' * 32, 'fixture')
                    self.assertEqual(result, 2)
                    self.assertIsNotNone(children[0].returncode, 'direct child was not reaped')
                    descendant = int(ready.read_text())
                    probe = subprocess.run(['ps', '-o', 'stat=', '-p', str(descendant)], capture_output=True, text=True)
                    self.assertTrue(probe.returncode != 0 or probe.stdout.strip().startswith('Z'), probe.stdout)
                    self.assertIsNone(unrelated.poll())
                    state = json.loads((root / 'session.json').read_text())
                    self.assertEqual(state['status'], 'failed')
                    self.assertIn('ps unavailable' if failure == 'monitor' else 'journal unavailable', state['error'])
                finally:
                    # Clean only the fixture's explicitly launched processes,
                    # including when running this regression against old code.
                    if ready.exists():
                        try:
                            os.kill(int(ready.read_text()), signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    for child in [*children, unrelated]:
                        if child.poll() is None:
                            child.kill()
                        child.wait(timeout=5)

    def test_reads_flutter_machine_start_from_mixed_log(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / 'stdout.log'
            log.write_text('ordinary Flutter output\n' + json.dumps([
                {'event': 'app.start', 'params': {'appId': 'app-42'}}]) + '\n')
            self.assertEqual(flutter_app_id(log), 'app-42')

    def test_tracks_escaped_descendant_and_rejects_stale_pid(self):
        entries = {10: (1, 10, 'supervisor'), 11: (10, 10, 'main'),
                   12: (11, 12, 'escaped'), 13: (1, 99, 'reused')}
        previous = {'13': {'started': 'old'}}
        owned = owned_processes(entries, 10, 10, 11, previous)
        self.assertEqual(set(owned), {11, 12})
        self.assertEqual(owned[12][1], 12)

    def test_stop_reaps_owned_child_but_not_unrelated_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
            try:
                code = ('import subprocess,sys,time; '
                        'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                        'print(p.pid,flush=True); sys.stdin.readline()')
                start = subprocess.run([sys.executable, str(TOOL), 'start', '--workspace', str(root),
                    '--cwd', str(root), '--run-id', 'a' * 32, '--storage', 'fixture-a', '--',
                    sys.executable, '-c', code], capture_output=True, text=True, timeout=15)
                self.assertEqual(start.returncode, 0, start.stderr)
                folder = Path(json.loads(start.stdout)['session'])
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and not (folder / 'stdout.log').read_text().strip():
                    time.sleep(.05)
                child = int((folder / 'stdout.log').read_text().strip())
                stopped = subprocess.run([sys.executable, str(TOOL), 'stop', '--session', str(folder)],
                                         capture_output=True, text=True, timeout=20)
                self.assertEqual(stopped.returncode, 0, stopped.stderr)
                state = json.loads((folder / 'session.json').read_text())
                self.assertEqual(state['status'], 'stopped')
                self.assertIn(str(child), state['observed'])
                self.assertIsNone(unrelated.poll())
                with self.assertRaises(ProcessLookupError):
                    os.kill(child, 0)
            finally:
                unrelated.terminate()
                unrelated.wait(timeout=5)

    def test_rejects_invalid_run_id(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run([sys.executable, str(TOOL), 'start', '--workspace', temporary,
                '--cwd', temporary, '--run-id', 'bad', '--storage', 'x', '--', sys.executable],
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(temporary) / 'build').exists())


if __name__ == '__main__':
    unittest.main()
