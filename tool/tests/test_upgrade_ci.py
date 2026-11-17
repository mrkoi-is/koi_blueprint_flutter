import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tool.upgrade_ci import (BASELINE_COMMITS, main, project_snapshot,
                             reviewed_references, verify_manual_migration)


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

    def test_archive_uses_immutable_baseline_commit_not_local_tag(self):
        expected = {
            'v0.2.0-rc.1': 'b880f35311ca59a7e8c21782d98ed8b4cc1e36f1',
            '5ec56a9': '5ec56a9774b68a9425f23882f620d479b03acf10',
        }
        self.assertEqual(BASELINE_COMMITS, expected)
        for label, commit in expected.items():
            output = self.root / ('out-' + label)
            argv = ['upgrade_ci.py', '--source', str(self.target), '--output', str(output),
                    '--baseline', label, '--template', 'minimal', '--device', 'linux']
            calls = []
            def capture(command, cwd, log):
                calls.append(command)
                raise RuntimeError('stop after archive request')
            with self.subTest(label=label), patch.object(sys, 'argv', argv), patch('tool.upgrade_ci.run', side_effect=capture):
                self.assertEqual(main(), 2)
            self.assertEqual(calls[0][-1], commit)
            summary = json.loads((output / 'summary.json').read_text())
            self.assertEqual((summary['baseline'], summary['baselineCommit']), (label, commit))
            self.assertFalse(summary['passed'])

    def migration_preview(self):
        return {'applicable': False, 'conflicts': [
            {'path': 'pubspec.yaml', 'reason': 'unsupported_managed_change'},
            *({'path': path, 'reason': 'dependency_resolution_required',
               'detail': 'unsupported upstream pubspec changes'}
              for path in ('apps/upgrade_ci_app/pubspec.yaml', 'packages/koi_core/pubspec.yaml')),
            self.conflict,
        ]}

    def verify_migration(self, preview=None):
        return verify_manual_migration(preview or self.migration_preview(), self.old,
            self.project, self.target, self.root / 'plan.json', self.root / 'rejected-apply.log')

    def test_manual_migration_requires_explicit_refusal_and_preserves_receipts(self):
        receipt = self.project / '.blueprint/baseline/receipt'
        receipt.parent.mkdir(parents=True)
        receipt.write_bytes(b'trusted baseline')
        before = project_snapshot(self.project)
        refusal = SimpleNamespace(returncode=2, stdout='Unresolved upgrade conflicts prevent applying the plan')
        with patch('tool.upgrade_ci.subprocess.run', return_value=refusal) as execute:
            result = self.verify_migration()
        self.assertEqual(execute.call_args.args[0][-2:], ['--plan', str(self.root / 'plan.json')])
        self.assertEqual(result['status'], 'manual_migration_required')
        self.assertFalse(result['upgradeApplied'])
        self.assertTrue(result['projectUnchanged'])
        self.assertEqual(before, project_snapshot(self.project))
        self.assertIn('.blueprint/baseline/receipt', before)

    def test_manual_migration_rejects_unexpected_conflicts_or_success(self):
        for change in ('applicable', 'extra', 'missing', 'resolver'):
            preview = self.migration_preview()
            if change == 'applicable':
                preview['applicable'] = True
            elif change == 'extra':
                preview['conflicts'].append({'path': 'lib/data.dart', 'reason': 'unsupported_managed_change'})
            elif change == 'missing':
                preview['conflicts'].pop(0)
            else:
                preview['conflicts'][1]['detail'] = 'resolver unavailable'
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'Unexpected migration boundary'):
                self.verify_migration(preview)
        for result in (SimpleNamespace(returncode=0, stdout='ok'),
                       SimpleNamespace(returncode=2, stdout='SDK missing')):
            with self.subTest(result=result), patch('tool.upgrade_ci.subprocess.run', return_value=result), self.assertRaisesRegex(ValueError, 'must reject apply'):
                self.verify_migration()

    def test_manual_migration_rejects_project_mutation_even_when_apply_fails(self):
        def mutate(*args, **kwargs):
            (self.project / 'user-data.json').write_text('changed')
            return SimpleNamespace(returncode=2, stdout='Unresolved upgrade conflicts prevent applying the plan')
        with patch('tool.upgrade_ci.subprocess.run', side_effect=mutate), self.assertRaisesRegex(ValueError, 'preserve the project'):
            self.verify_migration()


if __name__ == '__main__':
    unittest.main()
