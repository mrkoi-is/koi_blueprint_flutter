"""Measure explicit blueprint test runs without retries or replacing evidence."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time
import uuid

CASES = (
    ('app_vm', 'examples/ui_lab', 'test/ai_rename_journey_test.dart', 'vm', 1),
    ('app_chrome', 'examples/ui_lab', 'test/browser/ai_rename_journey_test.dart', 'chrome', 1),
    ('golden', 'packages/koi_ui', 'test/golden/status_golden_test.dart', 'vm', 3),
)


def percentile(values):
    ordered = sorted(values)
    return {'samples': len(ordered), 'median': statistics.median(ordered),
            'p95': ordered[math.ceil(len(ordered) * .95) - 1], 'max': ordered[-1]} if ordered else {
                'samples': 0, 'median': None, 'p95': None, 'max': None}


def parse_summary(output):
    candidates = []
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and isinstance(value.get('resultPath'), str):
            candidates.append(value)
    if len(candidates) != 1:
        raise ValueError('expected exactly one resultPath in this invocation')
    return candidates[0]


def run_case(root, output, case, timeout):
    name, member, path, target, expected = case
    command = [sys.executable, str(root / 'blueprint.py'), 'test', '--workspace', str(root),
               '--member', member, '--path', path, '--platform', target, '--timeout', str(timeout)]
    started = time.monotonic()
    error = None
    try:
        completed = subprocess.run(command, cwd=root, capture_output=True, text=True,
                                   encoding='utf-8', errors='replace', timeout=timeout + 90)
        stdout, stderr, code = completed.stdout, completed.stderr, completed.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or b'').decode('utf-8', errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        stderr = (exc.stderr or b'').decode('utf-8', errors='replace') if isinstance(exc.stderr, bytes) else (exc.stderr or '')
        code, error = None, 'outer_timeout'
    except OSError as exc:
        stdout, stderr, code, error = '', str(exc), None, 'launch_error'
    elapsed = round(time.monotonic() - started, 3)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'stdout.log').write_text(stdout, encoding='utf-8')
    (output / 'stderr.log').write_text(stderr, encoding='utf-8')
    result = None
    result_path = None
    try:
        summary = parse_summary(stdout)
        result_path = Path(summary['resultPath']).resolve()
        run_root = (root / 'build/test-runs').resolve()
        if result_path.name != 'result.json' or not result_path.is_relative_to(run_root):
            raise ValueError('resultPath outside workspace run evidence')
        result = json.loads(result_path.read_text(encoding='utf-8'))
        if result.get('runId') != result_path.parent.name or summary.get('status') != result.get('status'):
            raise ValueError('summary and result identity mismatch')
        if result.get('member') != member or result.get('requiredTargets') != [path] or result.get('environment', {}).get('target') != target:
            raise ValueError('unexpected result scope')
        if result.get('status') != 'passed':
            error = error or str(result.get('status', 'missing_status'))
        elif (code != 0 or result.get('executed') != expected or result.get('skipped') or
              result.get('evidenceComplete') is not True or result.get('scopeComplete') is not True):
            error = error or 'incomplete_evidence'
    except (ValueError, OSError, TypeError) as exc:
        error = error or 'invalid_result'
        stderr += f'\nResult verification: {exc}\n'
        (output / 'stderr.log').write_text(stderr, encoding='utf-8')
    source = (result or {}).get('source', {})
    return {'case': name, 'status': error or 'passed', 'exitCode': code,
            'cliSeconds': elapsed, 'processSeconds': (result or {}).get('process', {}).get('durationSeconds'),
            'runId': (result or {}).get('runId'), 'resultPath': str(result_path) if result_path else None,
            'sourceSha256': source.get('beforeSha256'), 'sourceChanged': source.get('changedDuringRun'),
            'stdout': str(output / 'stdout.log'), 'stderr': str(output / 'stderr.log'), 'argv': command}


def report(groups):
    repeats = groups[1:]
    counts = Counter(item['status'] for group in repeats for item in group['cases'] if item['status'] != 'passed')
    cases = {}
    for name, *_ in CASES:
        selected = [item for group in repeats for item in group['cases'] if item['case'] == name]
        cases[name] = {'cliSeconds': percentile([x['cliSeconds'] for x in selected]),
                       'processSeconds': percentile([x['processSeconds'] for x in selected
                                                     if isinstance(x['processSeconds'], (int, float))])}
    passed = sum(group['passed'] for group in repeats)
    return {'repeatGroups': len(repeats), 'passedGroups': passed,
            'firstPassRate': passed / len(repeats) if repeats else None,
            'failureClasses': dict(counts), 'cases': cases}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--groups', type=int, default=20, help='Repeat groups after first group (default 20)')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--cache-note', required=True, help='Describe actual pre-run cache state')
    args = parser.parse_args(argv)
    if args.groups < 1 or not 0 < args.timeout <= 3600 or not args.cache_note.strip():
        parser.error('groups must be positive, timeout within (0, 3600], cache note nonempty')
    root = args.workspace.resolve()
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:12]
    output = root / 'build/ai-testing/stability' / run_id
    output.mkdir(parents=True, exist_ok=False)
    groups = []
    reference_hash = None
    seen_run_ids = set()
    data = {'schemaVersion': 1, 'runId': run_id, 'requestedRepeatGroups': args.groups,
            'cacheNote': args.cache_note, 'environment': {'hostOS': platform.system(),
            'hostArch': platform.machine(), 'python': platform.python_version()}, 'groups': groups}
    for index in range(args.groups + 1):
        cases = []
        for case in CASES:
            item = run_case(root, output / f'group-{index:03d}' / case[0], case, args.timeout)
            run_id_for_case = item['runId']
            if run_id_for_case in seen_run_ids and item['status'] == 'passed':
                item['status'] = 'duplicate_run_id'
            if run_id_for_case:
                seen_run_ids.add(run_id_for_case)
            source_hash = item['sourceSha256']
            if source_hash and reference_hash is None:
                reference_hash = source_hash
            if not source_hash or source_hash != reference_hash or item['sourceChanged'] is not False:
                if item['status'] == 'passed':
                    item['status'] = 'source_changed_or_missing'
            cases.append(item)
        group = {'index': index, 'phase': 'first' if index == 0 else 'repeat',
                 'passed': all(item['status'] == 'passed' for item in cases), 'cases': cases}
        groups.append(group)
        data['sourceSha256'] = reference_hash
        data['statistics'] = report(groups)
        data['complete'] = len(groups) == args.groups + 1
        temp = output / 'summary.json.tmp'
        temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temp.replace(output / 'summary.json')
        print(f"group {index}/{args.groups}: {'passed' if group['passed'] else 'failed'}", flush=True)
    print(json.dumps({'resultPath': str(output / 'summary.json'), 'passed': all(g['passed'] for g in groups)}))
    return 0 if all(g['passed'] for g in groups) else 2


if __name__ == '__main__':
    raise SystemExit(main())
