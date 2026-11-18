import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tool.workspace_lock import WorkspaceBusy, workspace_lock


class WorkspaceLockTest(unittest.TestCase):
    def test_competition_and_release(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as other:
            root = Path(directory)
            with workspace_lock(root):
                with self.assertRaises(WorkspaceBusy):
                    with workspace_lock(root):
                        pass
                with workspace_lock(Path(other)):
                    pass
            with workspace_lock(root):
                pass

    def test_process_exit_releases_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            code = ('import os,sys; from pathlib import Path; '
                    'from tool.workspace_lock import workspace_lock; '
                    'lock=workspace_lock(Path(sys.argv[1])); lock.__enter__(); '
                    'print("locked",flush=True); os._exit(0)')
            child = subprocess.run([sys.executable, '-c', code, str(root)], capture_output=True, text=True)
            self.assertEqual(child.returncode, 0, child.stderr)
            self.assertIn('locked', child.stdout)
            with workspace_lock(root):
                pass


if __name__ == '__main__':
    unittest.main()
