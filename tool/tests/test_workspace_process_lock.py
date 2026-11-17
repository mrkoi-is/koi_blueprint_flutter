"""Cross-process workspace locking, including abrupt holder termination."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class WorkspaceProcessLockTest(unittest.TestCase):
    def test_competition_isolation_and_abrupt_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            holder_code = (
                'import sys,time; from pathlib import Path; '
                'from tool.workspace_lock import workspace_lock; '
                'lock=workspace_lock(Path(sys.argv[1])); lock.__enter__(); '
                'print("locked", flush=True); time.sleep(60)')
            probe_code = (
                'import sys; from pathlib import Path; '
                'from tool.workspace_lock import workspace_lock; '
                'lock=workspace_lock(Path(sys.argv[1])); lock.__enter__(); lock.__exit__(None,None,None)')
            holder = subprocess.Popen([sys.executable, '-c', holder_code, str(root / 'one')],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertEqual(holder.stdout.readline().strip(), 'locked')
                busy = subprocess.run([sys.executable, '-c', probe_code, str(root / 'one')],
                                      capture_output=True, text=True, timeout=15)
                self.assertNotEqual(busy.returncode, 0)
                self.assertIn('workspace_busy', busy.stderr)
                independent = subprocess.run([sys.executable, '-c', probe_code, str(root / 'two')],
                                             capture_output=True, text=True, timeout=15)
                self.assertEqual(independent.returncode, 0, independent.stderr)
            finally:
                holder.kill()
                holder.communicate(timeout=15)
            released = subprocess.run([sys.executable, '-c', probe_code, str(root / 'one')],
                                      capture_output=True, text=True, timeout=15)
            self.assertEqual(released.returncode, 0, released.stderr)


if __name__ == '__main__':
    unittest.main()
