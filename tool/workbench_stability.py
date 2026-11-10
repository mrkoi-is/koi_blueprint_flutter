"""Measure repeated Workbench persistence suites without retries."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import statistics
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tool.ai_test_ci import run_suite, verify_index
from tool.ai_test_workspace import resolve_workbench_member
from tool.platform_evidence import source_manifest


def statistics_for(groups):
    repeated = groups[1:]
    durations = sorted(item['durationSeconds'] for item in repeated)
    passed = sum(item['passed'] for item in repeated)
    return {
        'repeatGroups': len(repeated), 'passedGroups': passed,
        'firstPassRate': passed / len(repeated) if repeated else None,
        'failures': dict(Counter(item['failure'] for item in repeated if not item['passed'])),
        'durationSeconds': {
            'samples': len(durations),
            'median': statistics.median(durations) if durations else None,
            'p95': durations[math.ceil(len(durations) * .95) - 1] if durations else None,
            'max': max(durations) if durations else None,
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--member', help='Workbench member; defaults to the project metadata')
    parser.add_argument('--groups', type=int, default=10, help='Repeat groups after initial group')
    parser.add_argument('--cache-note', required=True)
    args = parser.parse_args(argv)
    if args.groups < 1 or not args.cache_note.strip():
        parser.error('groups must be positive and cache-note nonempty')
    root = args.workspace.resolve()
    try:
        args.member = resolve_workbench_member(root, args.member)
    except (OSError, ValueError, TypeError) as error:
        parser.error(str(error))
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:12]
    output = root / 'build/ai-testing/workbench-stability' / run_id
    output.mkdir(parents=True, exist_ok=False)
    groups = []
    seen_runs = set()
    reference = source_manifest(root)['source_sha256']
    summary = {'schemaVersion': 1, 'runId': run_id, 'member': args.member,
               'requestedRepeatGroups': args.groups, 'cacheNote': args.cache_note,
               'sourceSha256': reference, 'environment': {'hostOS': platform.system(),
               'hostArch': platform.machine(), 'python': platform.python_version()},
               'groups': groups, 'complete': False}
    for number in range(args.groups + 1):
        started = time.monotonic()
        group = {'index': number, 'phase': 'first' if number == 0 else 'repeat',
                 'passed': False, 'failure': None, 'runs': []}
        try:
            before = source_manifest(root)['source_sha256']
            index_path, suite_passed = run_suite(root, 'workbench', args.member)
            group['indexPath'] = str(index_path.relative_to(root))
            index = json.loads(index_path.read_text(encoding='utf-8'))
            after = source_manifest(root)['source_sha256']
            if before != reference or after != reference:
                raise ValueError('source_changed')
            for item in index['runs']:
                record = {'member': item.get('member'), 'target': item.get('target'),
                          'platform': item.get('platform'), 'passed': item.get('passed'),
                          'runId': item.get('runId'), 'result': item.get('result')}
                if item.get('result'):
                    if not item.get('runId') or item['runId'] in seen_runs:
                        raise ValueError('duplicate_or_missing_run_id')
                    seen_runs.add(item['runId'])
                    result = json.loads((root / item['result']).read_text(encoding='utf-8'))
                    if result.get('runId') != item['runId']:
                        raise ValueError('result_identity_mismatch')
                    source = result.get('source', {})
                    record['processSeconds'] = result.get('process', {}).get('durationSeconds')
                    record['sourceSha256'] = source.get('beforeSha256')
                    if (source.get('beforeSha256') != reference or source.get('afterSha256') != reference
                            or source.get('changedDuringRun') is not False):
                        raise ValueError('source_changed_or_missing')
                group['runs'].append(record)
            if not suite_passed:
                raise ValueError('suite_failed')
            checked = verify_index(root, index_path)
            if not checked['integrityVerified'] or not checked['suitePassed']:
                raise ValueError('invalid_suite_evidence')
            group['passed'] = True
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
            group['failure'] = str(error) or type(error).__name__
        group['durationSeconds'] = round(time.monotonic() - started, 3)
        groups.append(group)
        summary['statistics'] = statistics_for(groups)
        summary['complete'] = len(groups) == args.groups + 1
        summary['passed'] = summary['complete'] and all(item['passed'] for item in groups)
        temporary = output / '.summary.tmp'
        temporary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(output / 'summary.json')
        print(f"group {number}/{args.groups}: {'passed' if group['passed'] else 'failed'}", flush=True)
    print(json.dumps({'passed': summary['passed'], 'resultPath': str(output / 'summary.json')}))
    return 0 if summary['passed'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
