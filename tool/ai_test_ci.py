"""Run explicitly scoped AI regression checks and retain verifiable evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path, PurePosixPath, PureWindowsPath
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tool.ai_test_workspace import inspect_workspace, resolve_workbench_member


SUITES = {
    'app': (
        ('vm', 'examples/ui_lab', 'test/ai_rename_journey_test.dart', 1),
        ('chrome', 'examples/ui_lab', 'test/browser/ai_rename_journey_test.dart', 1),
    ),
    'golden': (('vm', 'packages/koi_ui', 'test/golden/status_golden_test.dart', 3),),
    'workbench': (
        ('vm', 'examples/workbench_app', 'test/ai_persistence_happy_test.dart', 2),
        ('vm', 'examples/workbench_app', 'test/ai_persistence_faults_test.dart', 4),
        ('chrome', 'examples/workbench_app', 'test/browser/ai_persistence_happy_browser_test.dart', 2),
        ('chrome', 'examples/workbench_app', 'test/browser/ai_persistence_faults_browser_test.dart', 4),
    ),
}

WORKBENCH_IDS = {
    'test/ai_persistence_happy_test.dart': {'W1', 'W5'},
    'test/browser/ai_persistence_happy_browser_test.dart': {'W1', 'W5'},
    'test/ai_persistence_faults_test.dart': {'W2', 'W3', 'W4', 'W6'},
    'test/browser/ai_persistence_faults_browser_test.dart': {'W2', 'W3', 'W4', 'W6'},
}


def protocol_relative(value: str) -> str:
    """Read schema 1 relative paths, including legacy Windows separators.

    Backslashes from older Windows producers are accepted, but drive-qualified,
    absolute, non-normalized and traversal paths never identify valid evidence.
    """
    if not isinstance(value, str) or not value or '\0' in value:
        raise ValueError('invalid relative evidence path')
    windows = PureWindowsPath(value)
    normalized = value.replace('\\', '/')
    path = PurePosixPath(normalized)
    if (windows.drive or windows.root or path.is_absolute() or normalized in ('', '.')
            or '..' in path.parts or str(path) != normalized):
        raise ValueError('invalid relative evidence path')
    return normalized


def verify_case_ids(events: Path, target: str) -> None:
    expected = WORKBENCH_IDS.get(target)
    if expected is None:
        return
    starts, actual = {}, []
    for line in events.read_text(encoding='utf-8').splitlines():
        event = json.loads(line)
        if event.get('type') == 'testStart':
            test = event['test']
            starts[test['id']] = test['name']
        elif (event.get('type') == 'testDone' and event.get('hidden') is False
              and event.get('skipped') is False and event.get('result') == 'success'):
            actual.append(starts[event['testID']].split(' ', 1)[0])
    if len(actual) != len(expected) or set(actual) != expected:
        raise ValueError(f'workbench case IDs mismatch: {actual}')


def suite_specs(suite: str, member: str | None = None) -> tuple:
    if member is not None:
        if suite != 'workbench':
            raise ValueError('--member is only supported for workbench')
        path = PurePosixPath(member)
        if (not member or '\\' in member or path.is_absolute() or
                '..' in path.parts or str(path) != member or member == '.'):
            raise ValueError('member must be a normalized workspace-relative path')
    return tuple((platform, member or default_member, target, count)
                 for platform, default_member, target, count in SUITES[suite])


def inspect_result(root: Path, summary: dict, code: int, previous: set[str],
                   platform: str, member: str, target: str, count: int) -> dict:
    """Reject missing, reused, incomplete or incorrectly scoped evidence."""
    runs = (root / 'build/test-runs').resolve()
    path = Path(summary['resultPath']).resolve()
    if path.name != 'result.json' or path.parent.parent != runs or path.parent.name in previous:
        raise ValueError('result is outside this invocation or was already present')
    result = json.loads(path.read_text(encoding='utf-8'))
    if result.get('runId') != path.parent.name:
        raise ValueError('runId does not match result directory')
    if (code != 0 or summary.get('status') != 'passed'
            or result.get('schemaVersion') != 1 or result.get('status') != 'passed'
            or result.get('evidenceComplete') is not True or result.get('scopeComplete') is not True
            or result.get('executed') != count or summary.get('executed') != count
            or result.get('skipped') != [] or result.get('missingTargets') != []
            or protocol_relative(result.get('member')) != member
            or [protocol_relative(p) for p in result.get('requiredTargets', [])] != [target]
            or result.get('nameFilter') is not None or result.get('environment', {}).get('target') != platform):
        raise ValueError('failed, incomplete, skipped or wrong-scope result')
    artifacts = result.get('artifacts', {})
    if not {'events.jsonl', 'stderr.log', 'source.json'} <= artifacts.keys():
        raise ValueError('missing mandatory artifacts')
    for name, info in artifacts.items():
        artifact = Path(info['path']).resolve()
        if not artifact.is_relative_to(path.parent) or not artifact.is_file():
            raise ValueError(f'missing or out-of-run artifact: {name}')
        if hashlib.sha256(artifact.read_bytes()).hexdigest() != info.get('sha256'):
            raise ValueError(f'artifact hash mismatch: {name}')
    verify_case_ids(path.parent / 'events.jsonl', target)
    return {'runId': result['runId'], 'result': path.relative_to(root).as_posix(),
            'member': member, 'target': target, 'platform': platform, 'executed': count,
            'resultSha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def run_suite(root: Path, suite: str, member: str | None = None) -> tuple[Path, bool]:
    root = root.resolve()
    kind, app = inspect_workspace(root)
    if suite == 'app' and kind != 'source':
        raise ValueError('UI Lab app suite is only available in the source workspace')
    if suite == 'workbench':
        member = resolve_workbench_member(root, member)
    specs = suite_specs(suite, member)
    output = root / 'build/ai-test-ci' / f'{suite}-{uuid.uuid4().hex}'
    output.mkdir(parents=True, exist_ok=False)
    index = {'schemaVersion': 1, 'suite': suite, 'runs': [], 'passed': False}
    if member is not None:
        index['member'] = member
    for position, (platform, member, target, count) in enumerate(specs):
        previous = {p.name for p in (root / 'build/test-runs').glob('*')}
        command = [sys.executable, str(root / 'blueprint.py'), 'test', '--workspace', str(root),
                   '--member', member, '--path', target, '--platform', platform]
        item = {'member': member, 'target': target, 'platform': platform,
                'stdout': f'{position}-stdout.log', 'stderr': f'{position}-stderr.log'}
        index['runs'].append(item)
        try:
            process = subprocess.run(command, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace')
            (output / item['stdout']).write_text(process.stdout, encoding='utf-8')
            (output / item['stderr']).write_text(process.stderr, encoding='utf-8')
            item['exitCode'] = process.returncode
            summaries = []
            for line in process.stdout.splitlines():
                try:
                    value = json.loads(line)
                    if isinstance(value, dict) and 'resultPath' in value:
                        summaries.append(value)
                except ValueError:
                    pass
            if len(summaries) != 1:
                raise ValueError('expected exactly one CLI result summary')
            # Preserve the returned result location even for failed runs, for diagnosis.
            returned = Path(summaries[0]['resultPath']).resolve()
            if (returned.name == 'result.json' and returned.parent.parent == (root / 'build/test-runs').resolve()
                    and returned.parent.name not in previous and returned.is_file()):
                item['result'] = returned.relative_to(root).as_posix()
                item['runId'] = returned.parent.name
                item['resultSha256'] = hashlib.sha256(returned.read_bytes()).hexdigest()
            item.update(inspect_result(root, summaries[0], process.returncode, previous,
                                       platform, member, target, count))
            item['passed'] = True
        except (OSError, ValueError, KeyError, TypeError) as error:
            item['passed'] = False
            item['error'] = str(error)
    index['passed'] = len(index['runs']) == len(specs) and all(x.get('passed') for x in index['runs'])
    path = output / 'index.json'
    path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return path, index['passed']


def verify_index(root: Path, index_path: Path) -> dict:
    """Verify extracted evidence, preserving the suite's original outcome."""
    root = root.resolve()
    index = json.loads(index_path.read_text(encoding='utf-8'))
    if index.get('suite') not in SUITES or type(index.get('passed')) is not bool:
        raise ValueError('invalid suite index')
    entries = index.get('runs', [])
    indexed_member = index.get('member')
    specs = suite_specs(index['suite'], protocol_relative(indexed_member) if indexed_member is not None else None)
    if len(entries) != len(specs):
        raise ValueError('incorrect suite size')
    replay, outcomes = [], []
    for item, (platform, member, target, count) in zip(entries, specs):
        if (item.get('platform'), protocol_relative(item.get('member')),
                protocol_relative(item.get('target'))) != (platform, member, target):
            raise ValueError('index scope mismatch')
        path = (root / protocol_relative(item['result'])).resolve()
        if not path.is_relative_to(root / 'build/test-runs') or path.name != 'result.json':
            raise ValueError('invalid result path')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item.get('resultSha256'):
            raise ValueError('result hash mismatch')
        result = json.loads(data)
        if (result.get('runId') != item.get('runId')
                or protocol_relative(result.get('member')) != member):
            raise ValueError('result identity mismatch')
        artifacts = result.get('artifacts', {})
        if not {'events.jsonl', 'stderr.log', 'source.json'} <= artifacts.keys():
            raise ValueError('missing mandatory artifacts')
        for name, info in artifacts.items():
            artifact = (path.parent / protocol_relative(name)).resolve()
            if not artifact.is_relative_to(path.parent) or not artifact.is_file():
                raise ValueError('missing or invalid extracted artifact')
            if hashlib.sha256(artifact.read_bytes()).hexdigest() != info.get('sha256'):
                raise ValueError('extracted artifact hash mismatch')
        if item.get('passed'):
            if (result.get('status') != 'passed' or result.get('evidenceComplete') is not True
                    or result.get('scopeComplete') is not True or result.get('executed') != count
                    or result.get('skipped') != [] or result.get('missingTargets') != []
                    or [protocol_relative(p) for p in result.get('requiredTargets', [])] != [target]
                    or result.get('nameFilter') is not None
                    or result.get('environment', {}).get('target') != platform):
                raise ValueError('passed result scope mismatch')
            verify_case_ids(path.parent / 'events.jsonl', target)
        outcomes.append({'runId': item['runId'], 'status': result.get('status'), 'accepted': bool(item.get('passed'))})
        replay.append([sys.executable, 'blueprint.py', 'test', '--member', member,
                       '--path', target, '--platform', platform])
    if index['passed'] != all(item.get('passed') is True for item in entries):
        raise ValueError('suite outcome mismatch')
    return {'integrityVerified': True, 'suitePassed': index['passed'],
            'runs': outcomes, 'replayFromCheckout': replay}


def stage_evidence(root: Path, destination: Path) -> None:
    """Create an artifact tree with a stable workspace-relative root."""
    root, destination = root.resolve(), destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    for relative in ('build/ai-test-ci', 'build/test-runs', 'packages/koi_ui/test/golden/failures'):
        source = root / relative
        if source.is_dir():
            shutil.copytree(source, destination / relative, dirs_exist_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--suite', choices=SUITES)
    parser.add_argument('--member', help='Workspace-relative Workbench member (workbench suite only)')
    parser.add_argument('--verify-index', type=Path, help='Verify extracted evidence; workspace points to its reconstructed root')
    parser.add_argument('--stage', type=Path, help='Copy evidence to a stable workspace-rooted artifact directory')
    args = parser.parse_args()
    if sum(bool(x) for x in (args.suite, args.verify_index, args.stage)) != 1:
        parser.error('select exactly one of --suite, --verify-index or --stage')
    if args.member is not None and args.suite != 'workbench':
        parser.error('--member requires --suite workbench')
    try:
        if args.verify_index:
            print(json.dumps(verify_index(args.workspace, args.verify_index)))
            return 0
        if args.stage:
            stage_evidence(args.workspace, args.stage)
            return 0
        path, passed = run_suite(args.workspace, args.suite, args.member)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Unable to retain CI evidence: {error}', file=sys.stderr)
        return 2
    print(json.dumps({'passed': passed, 'indexPath': str(path)}))
    return 0 if passed else 2


if __name__ == '__main__':
    raise SystemExit(main())
