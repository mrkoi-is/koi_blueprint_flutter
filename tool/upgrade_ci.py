"""Rebuild an old blueprint project and exercise its real upgrade in isolation."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def checked_file(root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or '..' in path.parts or str(path) != relative or not path.parts:
        raise ValueError(f'Unsafe reference path: {relative}')
    candidate = root.joinpath(*path.parts)
    if any(p.is_symlink() for p in (candidate, *candidate.parents) if p.is_relative_to(root)):
        raise ValueError(f'Symlink in reference path: {relative}')
    if not candidate.resolve().is_relative_to(root.resolve()) or not candidate.is_file():
        raise ValueError(f'Missing reference: {relative}')
    return candidate


def reviewed_references(conflicts: list, old_source: Path, project: Path, target: Path) -> dict:
    """Approve only references whose bytes exactly match the archived source."""
    resolutions = {}
    prefix = '.blueprint/reference/'
    for conflict in conflicts:
        path = conflict.get('path', '')
        if conflict.get('reason') != 'unmanaged_reference' or not path.startswith(prefix):
            raise ValueError(f'Unapproved upgrade conflict: {conflict}')
        origin = path[len(prefix):]
        before = checked_file(old_source, origin).read_bytes()
        current = checked_file(project, path).read_bytes()
        after = checked_file(target, origin).read_bytes()
        if (before != current or digest(current) != conflict.get('currentSha256')
                or digest(after) != conflict.get('targetSha256')):
            raise ValueError(f'Reference differs from archived or planned bytes: {path}')
        resolutions[path] = {'choice': 'take-upstream', 'currentSha256': digest(current),
                             'targetSha256': digest(after)}
    return resolutions


def run(argv: list[str], cwd: Path, log: Path) -> None:
    process = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding='utf-8', errors='replace')
    log.write_text('$ ' + ' '.join(argv) + '\n' + process.stdout, encoding='utf-8')
    if process.returncode:
        raise RuntimeError(f'Command failed ({process.returncode}); see {log}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', choices=('v0.2.0-rc.1', '5ec56a9'), required=True)
    parser.add_argument('--template', choices=('minimal', 'workbench'), required=True)
    parser.add_argument('--device', choices=('linux', 'macos'), required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be outside the source checkout')
    output.mkdir(parents=True, exist_ok=False)
    old, project = output / 'old-source', output / 'project'
    old.mkdir()
    summary = {'baseline': args.baseline, 'template': args.template, 'device': args.device,
               'passed': False, 'steps': []}
    try:
        archive = output / 'baseline.tar'
        run(['git', 'archive', '--format=tar', '--output', str(archive), args.baseline], source, output / 'archive.log')
        run(['tar', '-xf', str(archive), '-C', str(old)], source, output / 'extract.log')
        archive.unlink()
        platforms = 'web,' + args.device
        run([sys.executable, str(old / 'blueprint.py'), 'create', 'upgrade_ci', '--output', str(project),
             '--org', 'com.example', '--template', args.template, '--platforms', platforms], old, output / 'create.log')
        app = project / 'apps/upgrade_ci_app'
        initial, final, decisions = output / 'initial-plan.json', output / 'final-plan.json', output / 'resolutions.json'
        base = [sys.executable, str(source / 'blueprint.py'), 'upgrade', 'plan', '--app', str(app), '--source', str(source)]
        run(base + ['--output', str(initial)], source, output / 'initial-plan.log')
        preview = json.loads(initial.read_text(encoding='utf-8'))
        approved = reviewed_references(preview['conflicts'], old, project, source)
        decisions.write_text(json.dumps(approved, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        run(base + ['--output', str(final), '--resolutions', str(decisions)], source, output / 'final-plan.log')
        if not json.loads(final.read_text(encoding='utf-8')).get('applicable'):
            raise ValueError('Reviewed plan still contains conflicts')
        run([sys.executable, str(source / 'blueprint.py'), 'upgrade', 'apply', '--app', str(app), '--plan', str(final)], source, output / 'apply.log')
        cli = [sys.executable, str(project / 'blueprint.py')]
        run(cli + ['validate', '--workspace', str(project)], project, output / 'validate.log')
        target = 'test/app_test.dart' if args.template == 'minimal' else 'test/ai_persistence_happy_test.dart'
        run(cli + ['test', '--workspace', str(project), '--member', 'apps/upgrade_ci_app', '--path', target], project, output / 'targeted.log')
        if args.template == 'workbench':
            run([sys.executable, str(project / 'tool/ai_test_ci.py'), '--workspace', str(project), '--suite', 'workbench'], project, output / 'workbench.log')
            run(cli + ['build', '--app', str(app), '--platforms', args.device], project, output / 'build.log')
            command = [sys.executable, str(project / 'tool/workbench_restart_probe.py'), '--workspace', str(project),
                       '--member', 'apps/upgrade_ci_app', '--device', args.device]
            if args.device == 'linux':
                command = ['xvfb-run', '-a'] + command
            run(command, project, output / 'restart.log')
        if args.device == 'macos':
            run([sys.executable, str(project / 'tool/ai_test_ci.py'), '--workspace', str(project), '--suite', 'golden'], project, output / 'golden.log')
        summary['passed'] = True
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        summary['error'] = str(error)
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': summary['passed'], 'summary': str(output / 'summary.json')}))
    return 0 if summary['passed'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
