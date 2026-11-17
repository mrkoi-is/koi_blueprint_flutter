import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from tool.ai_test_stability import CASES, parse_summary, percentile, report, run_case


class StabilityTest(unittest.TestCase):
    def test_percentiles_and_empty_samples(self):
        self.assertEqual(percentile([])['p95'], None)
        self.assertEqual(percentile(list(range(1, 21))),
                         {'samples': 20, 'median': 10.5, 'p95': 19, 'max': 20})

    def test_summary_requires_single_result(self):
        text = 'informational log\n' + json.dumps({'resultPath': '/one'}) + '\n'
        self.assertEqual(parse_summary(text)['resultPath'], '/one')
        with self.assertRaises(ValueError):
            parse_summary(text + text)
        with self.assertRaises(ValueError):
            parse_summary('no JSON')

    def test_group_statistics_exclude_first_group(self):
        def group(status, seconds):
            return {'passed': status == 'passed', 'cases': [
                {'case': 'app_vm', 'status': status, 'cliSeconds': seconds, 'processSeconds': seconds / 2}]}
        result = report([group('failed', 100), group('passed', 4), group('failed', 2)])
        self.assertEqual(result['firstPassRate'], .5)
        self.assertEqual(result['failureClasses'], {'failed': 1})
        self.assertEqual(result['cases']['app_vm']['cliSeconds']['median'], 3)
        self.assertEqual(result['cases']['app_vm']['processSeconds']['max'], 2)

    def test_single_run_rejects_wrong_scope_and_empty_skip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_dir = root / 'build/test-runs/one'
            run_dir.mkdir(parents=True)
            result_path = run_dir / 'result.json'
            result = {'runId': 'one', 'status': 'passed', 'member': CASES[0][1],
                      'requiredTargets': [CASES[0][2]], 'environment': {'target': 'vm'},
                      'executed': 1, 'skipped': [], 'evidenceComplete': True, 'scopeComplete': True,
                      'process': {'durationSeconds': .5},
                      'source': {'beforeSha256': 'abc', 'changedDuringRun': False}}
            def execute(_command, **_kwargs):
                result_path.write_text(json.dumps(result), encoding='utf-8')
                return SimpleNamespace(returncode=0, stdout=json.dumps({'status': 'passed', 'resultPath': str(result_path)}), stderr='')
            with patch('tool.ai_test_stability.subprocess.run', side_effect=execute):
                actual = run_case(root, root / 'out1', CASES[0], 120)
                self.assertEqual(actual['status'], 'passed')
                result['skipped'] = ['required']
                self.assertEqual(run_case(root, root / 'out2', CASES[0], 120)['status'], 'incomplete_evidence')
                result['requiredTargets'] = ['test/other_test.dart']
                self.assertEqual(run_case(root, root / 'out3', CASES[0], 120)['status'], 'invalid_result')
            self.assertTrue((root / 'out3/stderr.log').is_file())


if __name__ == '__main__':
    unittest.main()
