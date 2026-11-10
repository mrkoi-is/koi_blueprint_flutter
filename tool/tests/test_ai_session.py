import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

from tool.ai_session import flutter_app_id, owned_processes


TOOL = Path(__file__).resolve().parents[1] / 'ai_session.py'


@unittest.skipUnless(os.name == 'posix', 'POSIX sessions required')
class AiSessionTest(unittest.TestCase):
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
