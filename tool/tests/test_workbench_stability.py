import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool import workbench_stability as stability


class WorkbenchStabilityTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        for name in ('ui_lab', 'workbench_app'):
            (self.root / 'examples' / name).mkdir(parents=True)
        self.calls = 0
        self.fail_at = None
        self.changed_at = None
        self.reuse_id = False
        self.expected_member = 'examples/workbench_app'

    def run_suite(self, root, suite, member):
        self.assertEqual((suite, member), ('workbench', self.expected_member))
        self.calls += 1
        run_id = f'run-{1 if self.reuse_id else self.calls}'
        run = root / 'build/test-runs' / run_id
        run.mkdir(parents=True, exist_ok=True)
        digest = 'changed' if self.calls == self.changed_at else 'source'
        result = {'runId': run_id, 'source': {'beforeSha256': digest,
                  'afterSha256': digest, 'changedDuringRun': False},
                  'process': {'durationSeconds': 1.2}}
        (run / 'result.json').write_text(json.dumps(result))
        passed = self.calls != self.fail_at
        index = root / 'build/ai-test-ci' / f'index-{self.calls}.json'
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text(json.dumps({'runs': [{'runId': run_id,
                         'result': str((run / 'result.json').relative_to(root)),
                         'passed': passed}]}))
        return index, passed

    def invoke(self, groups=2):
        args = ['--workspace', str(self.root), '--groups', str(groups),
                '--cache-note', 'SDK and build caches retained']
        with patch.object(stability, 'source_manifest', return_value={'source_sha256': 'source'}), \
             patch.object(stability, 'run_suite', side_effect=self.run_suite), \
             patch.object(stability, 'verify_index', return_value={'integrityVerified': True, 'suitePassed': True}):
            code = stability.main(args)
        path = next((self.root / 'build/ai-testing/workbench-stability').glob('*/summary.json'))
        return code, json.loads(path.read_text())

    def test_initial_plus_repeats_save_all_evidence(self):
        code, summary = self.invoke()
        self.assertEqual((code, self.calls), (0, 3))
        self.assertTrue(summary['complete'])
        self.assertEqual(summary['statistics']['passedGroups'], 2)
        self.assertEqual(summary['statistics']['firstPassRate'], 1)
        self.assertEqual(summary['statistics']['durationSeconds']['samples'], 2)
        self.assertEqual([g['phase'] for g in summary['groups']], ['first', 'repeat', 'repeat'])
        self.assertTrue(all(g['runs'][0]['processSeconds'] == 1.2 for g in summary['groups']))

    def test_failed_group_does_not_retry_or_hide_failure(self):
        self.fail_at = 2
        code, summary = self.invoke()
        self.assertEqual((code, self.calls), (2, 3))
        self.assertFalse(summary['passed'])
        self.assertEqual(summary['statistics']['failures'], {'suite_failed': 1})

    def test_source_change_in_individual_run_cannot_pass(self):
        self.changed_at = 2
        code, summary = self.invoke()
        self.assertEqual(code, 2)
        self.assertEqual(summary['groups'][1]['failure'], 'source_changed_or_missing')

    def test_reused_run_id_is_not_fresh(self):
        self.reuse_id = True
        code, summary = self.invoke()
        self.assertEqual(code, 2)
        self.assertEqual(summary['groups'][1]['failure'], 'duplicate_or_missing_run_id')

    def test_generated_member_comes_from_metadata(self):
        (self.root / 'apps/custom_app').mkdir(parents=True)
        (self.root / 'blueprint.json').write_text(json.dumps(
            {'schema': 2, 'template': 'workbench', 'app': 'apps/custom_app'}))
        self.expected_member = 'apps/custom_app'
        code, summary = self.invoke()
        self.assertEqual(code, 0)
        self.assertEqual(summary['member'], self.expected_member)

    def test_minimal_workspace_is_rejected(self):
        (self.root / 'apps/custom_app').mkdir(parents=True)
        (self.root / 'blueprint.json').write_text(json.dumps(
            {'schema': 2, 'template': 'minimal', 'app': 'apps/custom_app'}))
        with self.assertRaises(SystemExit) as error:
            self.invoke()
        self.assertEqual(error.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
