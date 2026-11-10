import hashlib
from pathlib import Path
import tempfile
import unittest

from tool.upgrade_ci import reviewed_references


def sha(data):
    return hashlib.sha256(data).hexdigest()


class UpgradeCiReviewTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.old, self.project, self.target = (self.root / name for name in ('old', 'project', 'target'))
        for root in (self.old, self.project, self.target):
            root.mkdir()
        self.relative = 'examples/demo/test.dart'
        self.path = '.blueprint/reference/' + self.relative
        for root, relative, data in ((self.old, self.relative, b'old'),
                                     (self.project, self.path, b'old'),
                                     (self.target, self.relative, b'new')):
            file = root / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
        self.conflict = {'path': self.path, 'reason': 'unmanaged_reference',
                         'currentSha256': sha(b'old'), 'targetSha256': sha(b'new')}

    def test_only_byte_identical_old_reference_is_approved(self):
        result = reviewed_references([self.conflict], self.old, self.project, self.target)
        self.assertEqual(result[self.path]['choice'], 'take-upstream')
        self.assertEqual(result[self.path]['targetSha256'], sha(b'new'))
        (self.project / self.path).write_bytes(b'custom')
        with self.assertRaisesRegex(ValueError, 'differs'):
            reviewed_references([self.conflict], self.old, self.project, self.target)

    def test_rejects_all_other_conflicts_and_bad_hashes(self):
        for change in ({'reason': 'unsupported_managed_change'},
                       {'path': '../escape'}, {'targetSha256': sha(b'other')}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                reviewed_references([{**self.conflict, **change}], self.old, self.project, self.target)

    def test_rejects_reference_symlink(self):
        path = self.project / self.path
        path.unlink()
        try:
            path.symlink_to(self.old / self.relative)
        except OSError:
            self.skipTest('Symlinks unavailable')
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            reviewed_references([self.conflict], self.old, self.project, self.target)


if __name__ == '__main__':
    unittest.main()
