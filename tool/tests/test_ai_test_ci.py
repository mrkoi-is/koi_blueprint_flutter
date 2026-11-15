import hashlib
import json
import shutil
from pathlib import Path
import tempfile
import unittest

from tool.ai_test_ci import (inspect_result, protocol_relative, stage_evidence, suite_specs,
                             verify_case_ids, verify_index)


class EvidenceCheckTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.run = self.root / 'build/test-runs/new-run'
        self.run.mkdir(parents=True)
        self.path = self.run / 'result.json'
        artifacts = {}
        for name in ('events.jsonl', 'stderr.log', 'source.json'):
            p = self.run / name
            p.write_text(name)
            artifacts[name] = {'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
        self.result = {'schemaVersion': 1, 'runId': 'new-run', 'status': 'passed',
                       'evidenceComplete': True, 'scopeComplete': True, 'executed': 3,
                       'skipped': [], 'missingTargets': [], 'member': 'packages/koi_ui',
                       'requiredTargets': ['test/golden/status_golden_test.dart'],
                       'nameFilter': None, 'environment': {'target': 'vm'}, 'artifacts': artifacts}
        self.summary = {'status': 'passed', 'executed': 3, 'resultPath': str(self.path)}

    def check(self, previous=None, code=0):
        self.path.write_text(json.dumps(self.result))
        return inspect_result(self.root, self.summary, code, previous or set(), 'vm',
                              'packages/koi_ui', 'test/golden/status_golden_test.dart', 3)

    def test_accepts_fresh_complete_result(self):
        self.assertEqual(self.check()['runId'], 'new-run')

    def test_rejects_skip_missing_zero_and_wrong_counts(self):
        for key, value in [('skipped', ['all']), ('executed', 0), ('executed', 2),
                           ('scopeComplete', False), ('missingTargets', ['file'])]:
            with self.subTest(key=key, value=value):
                old = self.result[key]
                self.result[key] = value
                with self.assertRaises(ValueError):
                    self.check()
                self.result[key] = old

    def test_rejects_stale_and_exit_failure(self):
        with self.assertRaises(ValueError):
            self.check({'new-run'})
        with self.assertRaises(ValueError):
            self.check(code=1)

    def test_rejects_missing_and_tampered_artifacts(self):
        (self.run / 'source.json').unlink()
        with self.assertRaises(ValueError):
            self.check()
        (self.run / 'source.json').write_text('wrong')
        with self.assertRaises(ValueError):
            self.check()

    def test_rejects_wrong_scope(self):
        self.result['requiredTargets'] = ['test/other_test.dart']
        with self.assertRaises(ValueError):
            self.check()

    def test_legacy_windows_result_is_normalized_without_weakening_scope(self):
        self.result['member'] = r'packages\koi_ui'
        self.result['requiredTargets'] = [r'test\golden\status_golden_test.dart']
        entry = self.check()
        self.assertEqual(entry['member'], 'packages/koi_ui')
        self.assertEqual(entry['target'], 'test/golden/status_golden_test.dart')
        self.assertEqual(entry['result'], 'build/test-runs/new-run/result.json')
        for member in (r'packages\..\koi_ui', r'C:\packages\koi_ui',
                       r'\packages\koi_ui', 'packages//koi_ui'):
            with self.subTest(member=member):
                self.result['member'] = member
                with self.assertRaises(ValueError):
                    self.check()

    def test_legacy_windows_evidence_replays_after_relocation(self):
        self.result['member'] = r'packages\koi_ui'
        self.result['requiredTargets'] = [r'test\golden\status_golden_test.dart']
        image = self.run / 'golden' / 'actual.png'
        image.parent.mkdir()
        image.write_bytes(b'image')
        self.result['artifacts'][r'golden\actual.png'] = {
            'path': r'C:\old-machine\build\test-runs\new-run\golden\actual.png',
            'sha256': hashlib.sha256(image.read_bytes()).hexdigest()}
        self.path.write_text(json.dumps(self.result), encoding='utf-8')
        extracted = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        shutil.copytree(self.run, extracted / 'build/test-runs/new-run')
        entry = {'runId': 'new-run', 'result': r'build\test-runs\new-run\result.json',
                 'resultSha256': hashlib.sha256(self.path.read_bytes()).hexdigest(),
                 'member': r'packages\koi_ui', 'target': r'test\golden\status_golden_test.dart',
                 'platform': 'vm', 'passed': True}
        index = extracted / 'index.json'
        index.write_text(json.dumps({'suite': 'golden', 'passed': True, 'runs': [entry]}), encoding='utf-8')
        verified = verify_index(extracted, index)
        self.assertTrue(verified['integrityVerified'])
        self.assertTrue(verified['suitePassed'])
        self.assertEqual(verified['replayFromCheckout'][0][3:7],
                         ['--member', 'packages/koi_ui', '--path', 'test/golden/status_golden_test.dart'])
        (extracted / 'build/test-runs/new-run/golden/actual.png').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            verify_index(extracted, index)
        entry['result'] = r'build\test-runs\..\outside\result.json'
        index.write_text(json.dumps({'suite': 'golden', 'passed': True, 'runs': [entry]}), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'invalid relative evidence path'):
            verify_index(extracted, index)
        (extracted / 'build/test-runs/new-run/golden/actual.png').write_bytes(b'image')
        self.result['artifacts'][r'..\outside.png'] = {'path': 'unused', 'sha256': '0' * 64}
        relocated_result = extracted / 'build/test-runs/new-run/result.json'
        relocated_result.write_text(json.dumps(self.result), encoding='utf-8')
        entry['result'] = r'build\test-runs\new-run\result.json'
        entry['resultSha256'] = hashlib.sha256(relocated_result.read_bytes()).hexdigest()
        index.write_text(json.dumps({'suite': 'golden', 'passed': True, 'runs': [entry]}), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'invalid relative evidence path'):
            verify_index(extracted, index)

    def test_legacy_path_normalization_rejects_drive_and_traversal(self):
        self.assertEqual(protocol_relative(r'test\browser\flow_test.dart'), 'test/browser/flow_test.dart')
        for value in ('', '.', '../outside', 'a/../b', r'..\outside', r'C:\outside',
                      r'C:relative', r'\\server\share\file', '/absolute', 'a//b', 'a/./b'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                protocol_relative(value)

    def test_extracted_evidence_is_portable_and_detects_tampering(self):
        entry = self.check()
        entry['passed'] = True
        extracted = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        shutil.copytree(self.run, extracted / 'build/test-runs/new-run')
        index = extracted / 'index.json'
        index.write_text(json.dumps({'suite': 'golden', 'passed': True, 'runs': [entry]}))
        replay = verify_index(extracted, index)
        self.assertTrue(replay['suitePassed'])
        self.assertEqual(replay['replayFromCheckout'][0][-2:], ['--platform', 'vm'])
        (extracted / 'build/test-runs/new-run/events.jsonl').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            verify_index(extracted, index)

    def test_failed_golden_evidence_retains_outcome_and_verifies_images(self):
        self.result['status'] = 'failed'
        image = self.run / 'golden/actual.png'
        image.parent.mkdir()
        image.write_bytes(b'image')
        self.result['artifacts']['golden/actual.png'] = {
            'path': str(image), 'sha256': hashlib.sha256(image.read_bytes()).hexdigest()}
        self.path.write_text(json.dumps(self.result))
        entry = {'runId': 'new-run', 'result': str(self.path.relative_to(self.root)),
                 'resultSha256': hashlib.sha256(self.path.read_bytes()).hexdigest(),
                 'member': 'packages/koi_ui', 'target': 'test/golden/status_golden_test.dart',
                 'platform': 'vm', 'passed': False}
        index_dir = self.root / 'build/ai-test-ci/golden-run'
        index_dir.mkdir(parents=True)
        (index_dir / 'index.json').write_text(json.dumps({'suite': 'golden', 'passed': False, 'runs': [entry]}))
        extracted = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        stage_evidence(self.root, extracted)
        index = extracted / 'build/ai-test-ci/golden-run/index.json'
        verified = verify_index(extracted, index)
        self.assertTrue(verified['integrityVerified'])
        self.assertFalse(verified['suitePassed'])
        self.assertEqual(verified['runs'][0]['status'], 'failed')
        (extracted / 'build/test-runs/new-run/golden/actual.png').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            verify_index(extracted, index)

    def test_staging_preserves_workspace_relative_paths_with_or_without_failures(self):
        failures = self.root / 'packages/koi_ui/test/golden/failures'
        failures.mkdir(parents=True)
        (failures / 'diff.png').write_bytes(b'diff')
        extracted = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        stage_evidence(self.root, extracted)
        self.assertTrue((extracted / 'build/test-runs/new-run').is_dir())
        self.assertTrue((extracted / 'packages/koi_ui/test/golden/failures/diff.png').is_file())

    def test_workbench_suite_covers_both_platforms_and_rejects_unsafe_member(self):
        specs = suite_specs('workbench', 'apps/ci_blueprint_app')
        self.assertEqual([spec[3] for spec in specs], [2, 4, 2, 4])
        self.assertEqual([spec[0] for spec in specs], ['vm', 'vm', 'chrome', 'chrome'])
        self.assertTrue(all(spec[1] == 'apps/ci_blueprint_app' for spec in specs))
        for member in ('../outside', '/absolute', '.', 'apps//example', 'apps\\example'):
            with self.subTest(member=member), self.assertRaises(ValueError):
                suite_specs('workbench', member)
        with self.assertRaises(ValueError):
            suite_specs('golden', 'apps/example')

    def test_workbench_generated_index_is_relocatable_and_scoped(self):
        entries = []
        specs = suite_specs('workbench', 'apps/ci_blueprint_app')
        for number, (platform, member, target, count) in enumerate(specs):
            run = self.root / 'build/test-runs' / f'run-{number}'
            run.mkdir(parents=True)
            artifacts = {}
            for name in ('events.jsonl', 'stderr.log', 'source.json'):
                path = run / name
                if name == 'events.jsonl':
                    identifiers = ['W1', 'W5'] if count == 2 else ['W2', 'W3', 'W4', 'W6']
                    events = []
                    for test_id, identifier in enumerate(identifiers):
                        events += [{'type': 'testStart', 'test': {'id': test_id, 'name': identifier + ' scenario'}},
                                   {'type': 'testDone', 'testID': test_id, 'result': 'success', 'hidden': False, 'skipped': False}]
                    path.write_text('\n'.join(json.dumps(event) for event in events))
                else:
                    path.write_text(name)
                artifacts[name] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            result = dict(self.result, runId=run.name, member=member,
                          requiredTargets=[target], executed=count,
                          environment={'target': platform}, artifacts=artifacts)
            path = run / 'result.json'
            path.write_text(json.dumps(result))
            summary = {'resultPath': str(path), 'status': 'passed', 'executed': count}
            entry = inspect_result(self.root, summary, 0, set(), platform, member, target, count)
            entries.append(dict(entry, passed=True))
        index = self.root / 'index.json'
        index.write_text(json.dumps({'suite': 'workbench', 'member': 'apps/ci_blueprint_app',
                                     'passed': True, 'runs': entries}))
        verified = verify_index(self.root, index)
        self.assertTrue(verified['suitePassed'])
        self.assertEqual(len(verified['replayFromCheckout']), 4)
        entries[2]['member'] = 'examples/workbench_app'
        index.write_text(json.dumps({'suite': 'workbench', 'member': 'apps/ci_blueprint_app',
                                     'passed': True, 'runs': entries}))
        with self.assertRaisesRegex(ValueError, 'scope mismatch'):
            verify_index(self.root, index)

    def test_workbench_ids_reject_missing_or_duplicate_cases(self):
        events = self.run / 'events.jsonl'
        def case(test_id, name):
            return [{'type': 'testStart', 'test': {'id': test_id, 'name': name}},
                    {'type': 'testDone', 'testID': test_id, 'result': 'success', 'hidden': False, 'skipped': False}]
        events.write_text('\n'.join(json.dumps(e) for e in case(1, 'W1 first') + case(2, 'W1 duplicate')))
        with self.assertRaisesRegex(ValueError, 'case IDs mismatch'):
            verify_case_ids(events, 'test/ai_persistence_happy_test.dart')


if __name__ == '__main__':
    unittest.main()
