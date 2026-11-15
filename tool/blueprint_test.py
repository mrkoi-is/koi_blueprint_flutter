"""Small, fail-closed adapter for explicit Flutter test files; no gate replacement."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import time
import uuid

from tool.platform_evidence import source_manifest


def protocol_path(path: Path) -> str:
    """Serialize a relative path independently of the executing host OS."""
    return path.as_posix()


def summarize(log: Path, exit_code: int | None, targets: list[Path], cwd: Path,
              *, timed_out=False) -> dict:
    """Interpret test reporter 0.1.1. A success summary alone is insufficient."""
    suites, starts, ends = {}, {}, {}
    errors, malformed, done, suite_counts = [], [], [], []
    start_count = 0
    last_type = None
    try:
        stream = log.read_text(encoding='utf-8').splitlines()
    except (OSError, UnicodeError) as error:
        stream = []
        malformed.append(str(error))
    for number, line in enumerate(stream, 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            kind = event['type']
            if not isinstance(kind, str) or last_type == 'done':
                raise ValueError('missing type or event after done')
            last_type = kind
            if kind == 'start':
                start_count += 1
                if event['protocolVersion'] != '0.1.1':
                    raise ValueError('unsupported reporter protocol')
            elif kind == 'suite':
                suite = event['suite']
                if suite['id'] in suites:
                    raise ValueError('duplicate suite')
                suites[suite['id']] = (cwd / suite['path']).resolve()
            elif kind == 'allSuites':
                if type(event['count']) is not int:
                    raise ValueError('invalid suite count')
                suite_counts.append(event['count'])
            elif kind == 'testStart':
                test = event['test']
                if not isinstance(test['name'], str):
                    raise ValueError('missing test name')
                if test['id'] in starts or test['suiteID'] not in suites:
                    raise ValueError('duplicate test or unknown suite')
                starts[test['id']] = test
            elif kind == 'testDone':
                if event['testID'] not in starts or event['testID'] in ends:
                    raise ValueError('unknown or duplicate test completion')
                if (event['result'] not in ('success', 'failure', 'error')
                        or type(event['skipped']) is not bool
                        or type(event['hidden']) is not bool):
                    raise ValueError('invalid test completion')
                ends[event['testID']] = event
            elif kind == 'error':
                errors.append(event)
            elif kind == 'done':
                if type(event['success']) is not bool:
                    raise ValueError('invalid completion')
                done.append(event['success'])
        except (ValueError, KeyError, TypeError) as error:
            malformed.append(f'line {number}: {error}')
    visible = {key: value for key, value in ends.items() if not value['hidden']}
    executed = {key: value for key, value in visible.items() if not value['skipped']}
    skipped = [starts[key]['name'] for key, value in visible.items() if value['skipped']]
    observed = {suites[starts[key]['suiteID']] for key in executed}
    missing = sorted(str(path) for path in set(targets) - observed)
    complete = (not malformed and start_count == 1 and len(done) == 1
                and last_type == 'done' and starts.keys() == ends.keys()
                and suite_counts == [len(suites)] and exit_code is not None)
    scope_complete = bool(executed) and not missing and not skipped
    failures = [starts[key]['name'] for key, value in visible.items()
                if value['result'] != 'success']
    if timed_out:
        status = 'timeout'
    elif failures:
        status = 'failed'
    elif complete and not executed and not errors and done == [True] and exit_code in (0, 79):
        # test_core's documented noTestsRan exit code, observed for --name
        # matching no cases. Require a complete event stream, not stderr text.
        status = 'not_run'
    elif errors or exit_code not in (0, None) or done == [False]:
        status = 'error'
    elif not complete:
        status = 'inconclusive'
    elif not executed:
        status = 'not_run'
    elif not scope_complete:
        status = 'inconclusive'
    else:
        status = 'passed'
    return {'status': status, 'reportedOutcome': done[0] if len(done) == 1 else None,
            'evidenceComplete': bool(complete and not timed_out),
            'scopeComplete': scope_complete, 'executed': len(executed),
            'skipped': skipped, 'missingTargets': missing, 'failures': failures,
            'errors': errors, 'protocolErrors': malformed}


def execute(argv: list[str], cwd: Path, output: Path, timeout: float) -> dict:
    """Each invocation owns its process group and writes fresh, separate streams."""
    started = time.monotonic()
    timed_out = interrupted = False
    cleanup = 'not_needed'
    code = None
    launch_error = None
    with (output / 'events.jsonl').open('wb') as stdout, (output / 'stderr.log').open('wb') as stderr:
        options = ({'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
                   if os.name == 'nt' else {'start_new_session': True})
        try:
            process = subprocess.Popen(argv, cwd=cwd, stdout=stdout, stderr=stderr, **options)
        except OSError as error:
            launch_error = str(error)
        else:
            try:
                code = process.wait(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                timed_out = isinstance(error, subprocess.TimeoutExpired)
                interrupted = not timed_out
                try:
                    if os.name == 'nt':
                        result = subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                                capture_output=True, timeout=10)
                        cleanup = 'terminated' if result.returncode == 0 else 'failed'
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                        cleanup = 'terminated'
                except ProcessLookupError:
                    cleanup = 'already_exited'
                except (OSError, subprocess.TimeoutExpired):
                    cleanup = 'failed'
                try:
                    code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    cleanup = 'failed'
    return {'exitCode': code, 'timedOut': timed_out, 'interrupted': interrupted,
            'cleanup': cleanup, 'launchError': launch_error,
            'durationSeconds': round(time.monotonic() - started, 3)}


def select_targets(root: Path, member_value: str, paths: list[str], workspace: list[Path]) -> tuple[Path, list[Path]]:
    member = (root / member_value).resolve()
    if member not in {path.resolve() for path in workspace}:
        raise ValueError('member must be an active workspace member')
    selected = []
    for value in paths:
        path = (member / value).resolve()
        if not path.is_relative_to(member / 'test') or not path.is_file() or not path.name.endswith('_test.dart'):
            raise ValueError('each --path must be an existing *_test.dart file inside the member test directory')
        if path in selected:
            raise ValueError('duplicate test path')
        selected.append(path)
    if not selected:
        raise ValueError('at least one test path is required')
    return member, selected


def golden_files(member: Path) -> dict[Path, tuple]:
    directory = member / 'test/golden/failures'
    return {path: (path.stat().st_mtime_ns, path.stat().st_size,
                   hashlib.sha256(path.read_bytes()).hexdigest())
            for path in directory.rglob('*')
            if path.is_file() and not path.is_symlink()}


def run_tests(root: Path, sdk, workspace: list[Path], args) -> dict:
    if not 0 < args.timeout <= 3600:
        raise ValueError('--timeout must be greater than 0 and at most 3600 seconds')
    member, targets = select_targets(root, args.member, args.path, workspace)
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:12]
    output = root / 'build/test-runs' / run_id
    output.mkdir(parents=True, exist_ok=False)
    argv = [str(sdk.flutter), 'test', '--no-pub', '--reporter', 'json']
    # Flutter's default tester reports VM suites, but --platform vm is invalid.
    if args.platform == 'chrome':
        argv += ['--platform', 'chrome']
    if args.name:
        argv += ['--name', args.name]
    relative_targets = [protocol_path(path.relative_to(member)) for path in targets]
    argv += relative_targets
    diagnostics = []
    before = after = None
    process = {'exitCode': None, 'timedOut': False, 'interrupted': False,
               'cleanup': 'not_needed', 'launchError': None, 'durationSeconds': 0}
    golden_artifacts = []
    result = {'status': 'error', 'reportedOutcome': None, 'evidenceComplete': False,
              'scopeComplete': False, 'executed': 0, 'skipped': [],
              'missingTargets': relative_targets, 'failures': [], 'errors': [],
              'protocolErrors': []}
    phase = 'source_before'
    try:
        before = source_manifest(root)
        (output / 'source.json').write_text(json.dumps(before, indent=2) + '\n', encoding='utf-8')
        phase = 'golden_before'
        previous_goldens = golden_files(member)
        phase = 'execute'
        process = execute(argv, member, output, args.timeout)
        phase = 'golden_collect'
        for path, identity in golden_files(member).items():
            if previous_goldens.get(path) != identity:
                destination = output / 'golden' / path.relative_to(member / 'test/golden/failures')
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                golden_artifacts.append(protocol_path(destination.relative_to(output)))
        phase = 'summarize'
        result = summarize(output / 'events.jsonl', process['exitCode'], targets, member,
                           timed_out=process['timedOut'])
        result['missingTargets'] = [protocol_path(Path(path).relative_to(member))
                                    for path in result['missingTargets']]
        phase = 'source_after'
        after = source_manifest(root)
        if before['source_sha256'] != after['source_sha256']:
            diagnostics.append({'kind': 'source_changed', 'message': 'Source changed during test'})
            result['evidenceComplete'] = False
            if result['status'] == 'passed':
                result['status'] = 'inconclusive'
    except (Exception, KeyboardInterrupt) as error:
        diagnostics.append({'kind': 'interrupted' if isinstance(error, KeyboardInterrupt)
                            else 'evidence_collection_failed',
                            'phase': phase, 'message': str(error) or type(error).__name__})
        result['status'] = 'error'
        result['evidenceComplete'] = False
    if process['launchError']:
        diagnostics.append({'kind': 'launch_failed', 'message': process['launchError']})
    if process['interrupted']:
        diagnostics.append({'kind': 'interrupted', 'message': 'Test process interrupted'})
    if process['cleanup'] == 'failed':
        diagnostics.append({'kind': 'cleanup_failed', 'message': 'Owned process cleanup failed'})
    if diagnostics and any(item['kind'] != 'source_changed' for item in diagnostics):
        result['status'] = 'error'
        result['evidenceComplete'] = False
    try:
        dirty = subprocess.run(['git', 'status', '--porcelain'], cwd=root,
                               capture_output=True, text=True, timeout=10)
        dirty_state = bool(dirty.stdout) if dirty.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        dirty_state = None
    artifacts = {}
    try:
        for name in ['events.jsonl', 'stderr.log', 'source.json', *golden_artifacts]:
            path = output / name
            if path.is_file():
                artifacts[name] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            else:
                raise OSError(f'Missing artifact: {name}')
    except OSError as error:
        diagnostics.append({'kind': 'evidence_collection_failed', 'phase': 'artifact_hash', 'message': str(error)})
        result['status'] = 'error'
        result['evidenceComplete'] = False
    before = before or {}
    after = after or {}
    try:
        flutter = json.loads((root / '.fvmrc').read_text())['flutter']
    except (OSError, ValueError, KeyError) as error:
        flutter = None
        diagnostics.append({'kind': 'evidence_collection_failed', 'phase': 'environment', 'message': str(error)})
        result['status'] = 'error'
        result['evidenceComplete'] = False
    result.update({'schemaVersion': 1, 'runId': run_id, 'attempt': 1,
                   'scope': 'explicit_files', 'member': protocol_path(member.relative_to(root)),
                   'requestedTargets': args.path, 'resolvedTargets': relative_targets,
                   'requiredTargets': relative_targets, 'nameFilter': args.name,
                   'selectionReason': 'explicit user selection; no downstream inference',
                   'source': {'commit': before.get('baseline_commit'), 'dirty': dirty_state,
                              'beforeSha256': before.get('source_sha256'),
                              'afterSha256': after.get('source_sha256'),
                              'changedDuringRun': (before.get('source_sha256') != after.get('source_sha256')) if after else None},
                   'environment': {'flutter': flutter, 'hostOS': platform.system(),
                                   'hostArch': platform.machine(), 'target': args.platform, 'mode': 'flutter_test'},
                   'process': process, 'deadlineSeconds': args.timeout,
                   'replay': {'argv': argv, 'cwd': str(member),
                              'member': protocol_path(member.relative_to(root)), 'paths': relative_targets,
                              'platform': args.platform, 'nameFilter': args.name},
                   'artifacts': artifacts, 'diagnostics': diagnostics,
                   'resultPath': str(output / 'result.json'),
                   'fullValidation': 'not_run', 'platformBuild': 'not_run'})
    # A reader sees either the complete result or no result, never partial JSON.
    temporary = output / '.result.json.tmp'
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, output / 'result.json')
    return result
