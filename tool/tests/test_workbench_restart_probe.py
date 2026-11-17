import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
import uuid
from unittest.mock import patch

from tool import workbench_restart_probe as probe
from tool.workspace_lock import WorkspaceBusy, workspace_lock


class RestartProbeTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.47.2'}))
        self.member = self.root / 'apps/demo_app'
        self.target = self.member / 'integration_test/ai_persistence_restart_test.dart'
        self.target.parent.mkdir(parents=True)
        self.target.touch()
        self.sdk = SimpleNamespace(flutter=self.root / 'flutter')

    def run_probe(self, *, phase_results=None, source_values=None, process_overrides=None):
        phase_results = phase_results or [True, True]
        source_values = source_values or ['same', 'same']
        calls = []

        def execute(argv, cwd, output, timeout):
            calls.append((argv, cwd, output, timeout))
            (output / 'events.jsonl').write_text('')
            (output / 'stderr.log').write_text('')
            report = argv[argv.index('--file-reporter') + 1]
            self.assertEqual(report, f'json:{output / "report.jsonl"}')
            (output / 'report.jsonl').write_text('report')
            result = {'exitCode': 0, 'timedOut': False, 'interrupted': False,
                      'cleanup': 'not_needed', 'launchError': None, 'durationSeconds': .1}
            result.update(process_overrides or {})
            return result

        def summarize(*args, **kwargs):
            self.assertEqual(args[0], calls[-1][2] / 'report.jsonl')
            passed = phase_results[len(calls) - 1]
            return {'status': 'passed' if passed else 'failed', 'executed': 1,
                    'evidenceComplete': True, 'scopeComplete': True}

        argv = ['workbench_restart_probe.py', '--workspace', str(self.root),
                '--member', 'apps/demo_app', '--device', 'macos']
        with patch('sys.argv', argv), patch.object(probe.blueprint, 'SDK', return_value=self.sdk), \
             patch.object(probe.blueprint, 'members', return_value=[self.member]), \
             patch.object(probe, 'source_manifest', side_effect=[{'source_sha256': s} for s in source_values]), \
             patch.object(probe, 'execute', side_effect=execute), \
             patch.object(probe, 'summarize', side_effect=summarize):
            code = probe.main()
        paths = list((self.root / 'build/ai-testing/workbench-restart').glob('*/result.json'))
        self.assertEqual(len(paths), 1)
        return code, json.loads(paths[0].read_text()), calls

    def test_two_processes_share_one_isolated_storage_and_run_in_order(self):
        code, result, calls = self.run_probe()
        self.assertEqual(code, 0)
        self.assertTrue(result['passed'])
        self.assertEqual([p['phase'] for p in result['phases']], ['write', 'read'])
        self.assertEqual(len(calls), 2)
        phase_args = [[arg for arg in call[0] if arg.startswith('--dart-define=KOI_TEST_PERSISTENCE_PHASE=')][0]
                      for call in calls]
        roots = [[arg for arg in call[0] if arg.startswith('--dart-define=KOI_TEST_STORAGE_ID=')][0]
                 for call in calls]
        self.assertEqual(phase_args, ['--dart-define=KOI_TEST_PERSISTENCE_PHASE=write',
                                      '--dart-define=KOI_TEST_PERSISTENCE_PHASE=read'])
        self.assertEqual(roots[0], roots[1])
        storage_id = roots[0].split('=', 2)[2]
        self.assertEqual(uuid.UUID(hex=storage_id).hex, storage_id)
        self.assertEqual(storage_id, result['runId'])
        self.assertEqual(result['flutter'], '3.47.2')
        output = calls[0][2].parent
        self.assertEqual(set(result['artifacts']),
                         {'source.json', 'write/events.jsonl', 'write/stderr.log', 'write/report.jsonl',
                          'read/events.jsonl', 'read/stderr.log', 'read/report.jsonl'})
        for relative, digest in result['artifacts'].items():
            self.assertEqual(hashlib.sha256((output / relative).read_bytes()).hexdigest(), digest)

    def test_failed_first_phase_does_not_run_read(self):
        code, result, calls = self.run_probe(phase_results=[False])
        self.assertEqual(code, 2)
        self.assertFalse(result['passed'])
        self.assertEqual(len(calls), 1)

    def test_source_change_cannot_pass(self):
        code, result, calls = self.run_probe(source_values=['before', 'after'])
        self.assertEqual(code, 2)
        self.assertFalse(result['passed'])
        self.assertEqual(len(calls), 2)

    def test_cleanup_failure_cannot_pass(self):
        code, result, calls = self.run_probe(process_overrides={'cleanup': 'failed'})
        self.assertEqual(code, 2)
        self.assertFalse(result['passed'])
        self.assertEqual(len(calls), 1)

    def test_interruption_cannot_pass(self):
        code, result, calls = self.run_probe(process_overrides={'interrupted': True})
        self.assertEqual(code, 2)
        self.assertFalse(result['passed'])
        self.assertEqual(len(calls), 1)

    def test_busy_workspace_stops_before_sdk(self):
        argv = ['probe', '--workspace', str(self.root), '--member', 'apps/demo_app', '--device', 'macos']
        with workspace_lock(self.root), patch('sys.argv', argv), \
             patch.object(probe.blueprint, 'SDK') as sdk:
            with self.assertRaises(WorkspaceBusy):
                probe.main()
            sdk.assert_not_called()

    def test_sdk_exception_produces_failed_result(self):
        argv = ['probe', '--workspace', str(self.root), '--member', 'apps/demo_app', '--device', 'macos']
        with patch('sys.argv', argv), patch.object(probe.blueprint, 'SDK', side_effect=ValueError('wrong sdk')):
            self.assertEqual(probe.main(), 2)
        path = next((self.root / 'build/ai-testing/workbench-restart').glob('*/result.json'))
        result = json.loads(path.read_text())
        self.assertFalse(result['passed'])
        self.assertIn('wrong sdk', result['error'])


if __name__ == '__main__':
    unittest.main()
