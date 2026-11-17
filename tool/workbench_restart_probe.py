"""Run write and read phases in distinct Flutter test processes with isolated storage."""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import blueprint
from tool.blueprint_test import execute, summarize
from tool.platform_evidence import source_manifest
from tool.workspace_lock import workspace_lock


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--member', required=True)
    parser.add_argument('--device', choices=('macos', 'linux', 'windows'), required=True)
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        parser.error('--timeout must be greater than zero and at most 3600 seconds')
    root = args.workspace.resolve()
    with workspace_lock(root):
        return run_probe(root, args)


def run_probe(root, args):
    member = (root / args.member).resolve()
    run_id = uuid.uuid4().hex
    output = root / 'build/ai-testing/workbench-restart' / run_id
    output.mkdir(parents=True)
    result = {'schemaVersion': 1, 'runId': run_id, 'device': args.device,
              'member': args.member, 'phases': [], 'passed': False,
              'environment': {'hostOS': platform.system(), 'hostArch': platform.machine()},
              'replay': ['python', 'tool/workbench_restart_probe.py', '--workspace', '.',
                         '--member', args.member, '--device', args.device]}
    try:
        sdk = blueprint.SDK(root)
        if member not in {p.resolve() for p in blueprint.members(root, sdk)}:
            raise ValueError('member must be active')
        target = member / 'integration_test/ai_persistence_restart_test.dart'
        if not target.is_file():
            raise ValueError('restart test not found')
        manifest = source_manifest(root)
        (output / 'source.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        before = manifest['source_sha256']
        result['flutter'] = blueprint.pinned_flutter_version(root)
        for phase in ('write', 'read'):
            phase_dir = output / phase
            phase_dir.mkdir()
            report = phase_dir / 'report.jsonl'
            argv = [str(sdk.flutter), 'test', '--no-pub', '--reporter', 'expanded',
                    '--file-reporter', f'json:{report}',
                    '-d', args.device, f'--dart-define=KOI_TEST_STORAGE_ID={run_id}',
                    f'--dart-define=KOI_TEST_PERSISTENCE_PHASE={phase}', str(target.relative_to(member))]
            process = execute(argv, member, phase_dir, args.timeout)
            evidence = summarize(report, process['exitCode'], [target], member,
                                 timed_out=process['timedOut'])
            passed = (evidence['status'] == 'passed' and evidence['executed'] == 1
                      and evidence['evidenceComplete'] and evidence['scopeComplete']
                      and process['cleanup'] != 'failed' and not process['interrupted'])
            result['phases'].append({'phase': phase, 'process': process, 'evidence': evidence,
                                     'passed': bool(passed), 'argv': argv})
            if not passed:
                break
        after = source_manifest(root)['source_sha256']
        result.update({'sourceBefore': before, 'sourceAfter': after,
                       'passed': len(result['phases']) == 2 and all(p['passed'] for p in result['phases']) and before == after})
    except (Exception, KeyboardInterrupt) as error:
        result['error'] = f'{type(error).__name__}: {error}'
    result['artifacts'] = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in output.rglob('*') if p.is_file()}
    path = output / 'result.json'
    staging = output / '.result.tmp'
    staging.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    staging.replace(path)
    print(json.dumps({'passed': result['passed'], 'resultPath': str(path)}))
    return 0 if result['passed'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
