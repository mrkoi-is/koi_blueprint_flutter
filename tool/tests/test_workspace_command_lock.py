from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import blueprint
from tool.workspace_lock import workspace_lock


class CommandLockTest(unittest.TestCase):
    def test_busy_rejects_test_validate_and_test_phases_before_action(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with workspace_lock(root):
                for command in (['test', '--member', 'x', '--path', 'test/x_test.dart'],
                                ['validate'], ['check', 'test'],
                                ['check', 'browser'], ['check', 'coverage']):
                    with self.subTest(command=command), patch.object(blueprint, 'SDK') as sdk:
                        self.assertEqual(blueprint.main([*command, '--workspace', str(root)]), 2)
                        sdk.assert_not_called()

    def test_unrelated_check_does_not_request_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            with workspace_lock(Path(temporary)), patch.object(blueprint, 'check') as check:
                self.assertEqual(blueprint.main(['check', 'ai', '--workspace', temporary]), 0)
                check.assert_called_once()

    def test_upgrade_and_capability_writes_share_test_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / 'apps' / 'demo'
            app.mkdir(parents=True)
            (root / 'pubspec.yaml').write_text('name: demo\nworkspace:\n  - apps/demo\n')
            with workspace_lock(root):
                for command in (['upgrade', 'apply', '--app', str(app), '--plan', 'unused'],
                                ['upgrade', 'rollback', '--app', str(app), '--transaction', 'unused'],
                                ['capability', 'add', '--app', str(app), 'unused']):
                    with self.subTest(command=command):
                        self.assertEqual(blueprint.main(command), 2)


if __name__ == '__main__':
    unittest.main()
