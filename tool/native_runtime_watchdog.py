#!/usr/bin/env python3
"""Run the Linux native smoke in an owned process group with a hard deadline."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def _group_exists(group: int) -> bool:
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def run(command: list[str], log: Path, report: Path, timeout: float, grace: float,
        events: Path | None = None, target: Path | None = None) -> int:
    if os.name != 'posix':
        raise ValueError('native runtime watchdog requires POSIX process groups')
    if not command or timeout <= 0 or grace <= 0:
        raise ValueError('command, positive timeout and positive grace are required')
    if (events is None) != (target is None):
        raise ValueError('events and target must be specified together')
    # Refuse old files: neither successful nor failed runs may borrow old logs.
    if log.exists() or report.exists() or (events is not None and events.exists()):
        raise ValueError('runtime log or supervisor report already exists')
    start = time.monotonic()
    state = {'schemaVersion': 1, 'argv': command, 'timedOut': False,
             'exitCode': None, 'cleanup': 'not_needed', 'passed': False}
    errors: list[str] = []
    with log.open('xb') as output:
        lock = threading.Lock()

        def publish(data: bytes) -> None:
            with lock:
                try:
                    output.write(data)
                    output.flush()
                except OSError as error:
                    errors.append(f'log: {error}')
                try:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                except (OSError, BrokenPipeError) as error:
                    errors.append(f'stdout: {error}')

        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, start_new_session=True,
                                       bufsize=0)
        except OSError as error:
            state['error'] = f'launch: {error}'
            publish(f'KOI_WATCHDOG launch failed: {error}\n'.encode())
            code = 127
        else:
            assert process.stdout is not None

            def relay() -> None:
                try:
                    while data := process.stdout.read(4096):
                        publish(data)
                except OSError as error:
                    errors.append(f'relay: {error}')

            reader = threading.Thread(target=relay, daemon=True)
            reader.start()
            try:
                state['exitCode'] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                state['timedOut'] = True
                publish(f'KOI_WATCHDOG timeout after {timeout:g}s; stopping process group {process.pid}\n'.encode())
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                deadline = time.monotonic() + grace
                while _group_exists(process.pid) and time.monotonic() < deadline:
                    process.poll()
                    time.sleep(.05)
                if _group_exists(process.pid):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                try:
                    state['exitCode'] = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    errors.append('direct child did not terminate after SIGKILL')
                state['cleanup'] = 'terminated' if not _group_exists(process.pid) else 'group_still_present'
            except KeyboardInterrupt:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                state['cleanup'] = 'interrupted'
                errors.append('supervisor interrupted')
                try:
                    state['exitCode'] = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    errors.append('direct child did not terminate after interrupt')
            # A normally exiting wrapper must not leave owned descendants running.
            if not state['timedOut'] and _group_exists(process.pid):
                deadline = time.monotonic() + .5
                while _group_exists(process.pid) and time.monotonic() < deadline:
                    time.sleep(.05)
            if not state['timedOut'] and _group_exists(process.pid):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                state['cleanup'] = 'unexpected_descendants'
                errors.append('process group survived direct child')
            reader.join(timeout=5)
            if reader.is_alive():
                errors.append('output pipe still open after process exit')
            code = (124 if state['timedOut'] else
                    2 if errors else
                    state['exitCode'] if isinstance(state['exitCode'], int) and 0 <= state['exitCode'] <= 125 else 1)
    if events is not None and target is not None:
        # Integration test success is accepted only with its own complete JSON
        # reporter stream and exactly one actual, non-skipped visible test.
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from tool.blueprint_test import summarize
        evidence = summarize(events, state['exitCode'], [target.resolve()], Path.cwd(),
                             timed_out=state['timedOut'])
        state['evidence'] = evidence
        if code == 0 and not (evidence['status'] == 'passed' and
                              evidence['evidenceComplete'] and evidence['scopeComplete'] and
                              evidence['executed'] == 1 and not evidence['skipped']):
            errors.append('reporter evidence did not prove one completed test')
            code = 2
    state['durationSeconds'] = round(time.monotonic() - start, 3)
    state['errors'] = errors
    state['passed'] = code == 0 and not errors
    staging = report.with_name(report.name + '.tmp')
    try:
        with staging.open('x', encoding='utf-8') as file:
            json.dump(state, file, ensure_ascii=False, indent=2)
            file.write('\n')
        os.replace(staging, report)
    except OSError as error:
        print(f'KOI_WATCHDOG cannot write report: {error}', file=sys.stderr)
        return 2
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('--grace', type=float, default=10)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--events', type=Path, help='Fresh JSON reporter output')
    parser.add_argument('--target', type=Path, help='Required test file')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    # GitHub's Linux runner sends SIGTERM on cancellation. Route it through the
    # same owned-group cleanup path as a local interrupt rather than orphaning
    # the separate session started below.
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt()

    if os.name == 'posix':
        signal.signal(signal.SIGTERM, interrupted)
    try:
        return run(command, args.log, args.report, args.timeout, args.grace,
                   args.events, args.target)
    except (OSError, ValueError) as error:
        print(f'KOI_WATCHDOG {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
