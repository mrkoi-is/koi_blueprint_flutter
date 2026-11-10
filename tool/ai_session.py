#!/usr/bin/env python3
"""Own a local debug process session and stop only processes in that session.

This is a POSIX development helper, not a wrapper for arbitrary MCP launches.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid


def publish(path: Path, value: dict) -> None:
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def processes() -> dict[int, tuple[int, int, str]]:
    result = subprocess.run(['ps', '-axo', 'pid=,ppid=,lstart='],
                            capture_output=True, text=True, check=True)
    entries = {}
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=2)
        if len(parts) == 3:
            try:
                pid = int(parts[0])
                entries[pid] = (int(parts[1]), os.getsid(pid), parts[2])
            except (ValueError, ProcessLookupError, PermissionError):
                continue
    return entries


def owned_processes(entries: dict, supervisor_pid: int, session_id: int,
                    root_pid: int, observed: dict) -> dict:
    """Find session members and previously observed descendants by identity."""
    owned = {pid for pid, (parent, sid, _) in entries.items()
             if sid == session_id and pid != supervisor_pid
             and (parent != supervisor_pid or pid == root_pid)}
    owned.update(pid for pid, (_, _, started) in entries.items()
                 if str(pid) in observed and observed[str(pid)]['started'] == started)
    while True:
        more = {pid for pid, (parent, _, _) in entries.items()
                if parent in owned and pid != supervisor_pid}
        if more <= owned:
            break
        owned.update(more)
    return {pid: entries[pid] for pid in owned}


def flutter_app_id(log: Path) -> str | None:
    """Read the Flutter machine app.start event, ignoring ordinary log lines."""
    for line in log.read_text(encoding='utf-8', errors='replace').splitlines():
        try:
            events = json.loads(line)
        except ValueError:
            continue
        if isinstance(events, list):
            for event in events:
                if isinstance(event, dict) and event.get('event') == 'app.start':
                    value = event.get('params', {}).get('appId')
                    if isinstance(value, str) and value:
                        return value
    return None


def supervise(folder: Path, cwd: Path, command: list[str], run_id: str, storage: str) -> int:
    session_id = os.getsid(0)
    state = {'schemaVersion': 1, 'runId': run_id, 'storage': storage,
             'cwd': str(cwd), 'command': command, 'supervisorPid': os.getpid(),
             'sessionId': session_id, 'status': 'starting', 'observed': {}}
    status = folder / 'session.json'
    try:
        with (folder / 'stdout.log').open('wb') as stdout, (folder / 'stderr.log').open('wb') as stderr:
            process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE, stdout=stdout, stderr=stderr)
            state.update({'status': 'running', 'processPid': process.pid})
            publish(status, state)
            stopping = None
            sent_term = sent_kill = False
            while True:
                process.poll()  # Reap the direct child before enumerating the session.
                entries = processes()
                owned = owned_processes(entries, os.getpid(), session_id, process.pid, state['observed'])
                members = {pid: info for pid, info in owned.items() if info[1] == session_id}
                escaped = {pid: info for pid, info in owned.items() if info[1] != session_id}
                for pid, (_, sid, started) in owned.items():
                    state['observed'][str(pid)] = {'sessionId': sid, 'started': started}
                if (folder / 'stop.request').exists() and stopping is None:
                    stopping = time.monotonic()
                    state['status'] = 'stopping'
                    try:
                        if process.stdin:
                            if '--machine' in command:
                                app_id = flutter_app_id(folder / 'stdout.log')
                                if app_id:
                                    request = [{'id': 1, 'method': 'app.stop', 'params': {'appId': app_id}}]
                                    process.stdin.write((json.dumps(request) + '\n').encode())
                                else:
                                    state['gracefulStopUnavailable'] = 'missing app.start event'
                            else:
                                process.stdin.write(b'q\n')
                            process.stdin.flush()
                    except (BrokenPipeError, OSError):
                        pass
                    publish(status, state)
                if stopping is not None:
                    elapsed = time.monotonic() - stopping
                    sig = signal.SIGKILL if elapsed >= 8 and not sent_kill else signal.SIGTERM if elapsed >= 3 and not sent_term else None
                    if sig:
                        # Each target is rechecked immediately against the current OS
                        # session and start identity, never a stale PID from disk.
                        current = processes()
                        for pid, (_, sid, started) in members.items():
                            if current.get(pid, (None, None, None))[1:] == (sid, started):
                                try:
                                    os.kill(pid, sig)
                                except ProcessLookupError:
                                    pass
                        sent_term |= sig == signal.SIGTERM
                        sent_kill |= sig == signal.SIGKILL
                    if not members and not escaped:
                        process.poll()
                        state.update({'status': 'stopped', 'exitCode': process.returncode,
                                      'sentTerm': sent_term, 'sentKill': sent_kill})
                        publish(status, state)
                        return 0
                    if elapsed >= 12:
                        raise RuntimeError(f'owned processes did not exit; escaped session PIDs: {sorted(escaped)}')
                elif process.poll() is not None and not owned:
                    state.update({'status': 'exited', 'exitCode': process.returncode})
                    publish(status, state)
                    return 0
                time.sleep(.15)
    except Exception as error:
        state.update({'status': 'failed', 'error': f'{type(error).__name__}: {error}'})
        publish(status, state)
        return 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    start = commands.add_parser('start')
    start.add_argument('--workspace', type=Path, required=True)
    start.add_argument('--cwd', type=Path, required=True)
    start.add_argument('--run-id', required=True)
    start.add_argument('--storage', required=True, help='Printed isolated storage location or identifier; never deleted')
    start.add_argument('command', nargs=argparse.REMAINDER)
    stop = commands.add_parser('stop')
    stop.add_argument('--session', type=Path, required=True)
    internal = commands.add_parser('_supervise')
    internal.add_argument('--folder', type=Path, required=True)
    internal.add_argument('--cwd', type=Path, required=True)
    internal.add_argument('--run-id', required=True)
    internal.add_argument('--storage', required=True)
    internal.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if os.name != 'posix':
        parser.error('session ownership currently requires POSIX')
    if args.action == '_supervise':
        return supervise(args.folder, args.cwd, args.command, args.run_id, args.storage)
    if args.action == 'start':
        if not re.fullmatch(r'[0-9a-f]{32}', args.run_id):
            parser.error('run ID must be 32 lowercase hexadecimal characters')
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        if not command:
            parser.error('command is required after --')
        workspace, cwd = args.workspace.resolve(), args.cwd.resolve()
        if not cwd.is_dir() or not cwd.is_relative_to(workspace):
            parser.error('cwd must be an existing directory inside the workspace')
        folder = workspace / 'build/ai-testing/sessions' / uuid.uuid4().hex
        folder.mkdir(parents=True, exist_ok=False)
        with (folder / 'supervisor.log').open('wb') as log:
            supervisor = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '_supervise',
                '--folder', str(folder), '--cwd', str(cwd), '--run-id', args.run_id,
                '--storage', args.storage, *command], stdout=log, stderr=log, start_new_session=True)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if (folder / 'session.json').is_file():
                value = json.loads((folder / 'session.json').read_text(encoding='utf-8'))
                print(json.dumps({'session': str(folder), 'status': value['status']}))
                return 0 if value['status'] == 'running' else 2
            if supervisor.poll() is not None:
                break
            time.sleep(.05)
        print(f'supervisor did not start; inspect {folder}', file=sys.stderr)
        return 2
    folder = args.session.resolve()
    status = folder / 'session.json'
    try:
        value = json.loads(status.read_text(encoding='utf-8'))
        if value.get('status') not in ('running', 'stopping'):
            raise ValueError(f"session is not running: {value.get('status')}")
        (folder / 'stop.request').touch(exist_ok=True)
        deadline = time.monotonic() + 16
        while time.monotonic() < deadline:
            value = json.loads(status.read_text(encoding='utf-8'))
            if value.get('status') in ('stopped', 'failed', 'exited'):
                print(json.dumps({'session': str(folder), 'status': value['status']}))
                return 0 if value['status'] == 'stopped' else 2
            time.sleep(.1)
        raise ValueError('supervisor did not confirm shutdown; inspect session logs')
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
