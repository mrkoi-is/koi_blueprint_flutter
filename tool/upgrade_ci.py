"""Rebuild an old blueprint project and exercise its real upgrade in isolation."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys

# Release candidate tag was local-only and is not necessarily present in a
# remote clone. Resolve every supported label to its reviewed immutable commit.
BASELINE_COMMITS = {
    'v0.2.0-rc.1': 'b880f35311ca59a7e8c21782d98ed8b4cc1e36f1',
    '5ec56a9': '5ec56a9774b68a9425f23882f620d479b03acf10',
}


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


def project_snapshot(root: Path) -> dict[str, str]:
    """Hash project data and receipts, excluding only disposable tool caches."""
    ignored = {'.git', '.dart_tool', '.fvm', 'build', 'coverage', 'Pods',
               'ephemeral', '.symlinks', '.gradle', '__pycache__'}
    files = {}
    for directory, folders, names in os.walk(root, followlinks=False):
        for name in list(folders):
            path = Path(directory) / name
            if name in ignored:
                folders.remove(name)
            elif path.is_symlink():
                files[path.relative_to(root).as_posix()] = 'link:' + os.readlink(path)
                folders.remove(name)
        for name in names:
            path = Path(directory) / name
            if name.endswith('.pyc'):
                continue
            files[path.relative_to(root).as_posix()] = (
                'link:' + os.readlink(path) if path.is_symlink() else digest(path.read_bytes()))
    return files


def verify_manual_migration(preview: dict, old: Path, project: Path,
                            source: Path, plan: Path, log: Path) -> dict:
    """Verify the reviewed v0.3 dependency boundary, never accept arbitrary failures."""
    expected = {
        ('pubspec.yaml', 'unsupported_managed_change'),
        ('apps/upgrade_ci_app/pubspec.yaml', 'dependency_resolution_required'),
        ('packages/koi_core/pubspec.yaml', 'dependency_resolution_required'),
    }
    conflicts = preview['conflicts']
    blocking = [c for c in conflicts if c.get('reason') != 'unmanaged_reference']
    if (preview.get('applicable') is not False or len(blocking) != len(expected)
            or {(c.get('path'), c.get('reason')) for c in blocking} != expected
            or any(c.get('detail') != 'unsupported upstream pubspec changes'
                   for c in blocking if c['reason'] == 'dependency_resolution_required')):
        raise ValueError('Unexpected migration boundary; review the complete plan')
    reviewed_references([c for c in conflicts if c.get('reason') == 'unmanaged_reference'],
                        old, project, source)
    before = project_snapshot(project)
    command = [sys.executable, str(source / 'blueprint.py'), 'upgrade', 'apply',
               '--app', str(project / 'apps/upgrade_ci_app'), '--plan', str(plan)]
    result = subprocess.run(command, cwd=source, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    log.write_text('$ ' + ' '.join(command) + '\n' + result.stdout, encoding='utf-8')
    after = project_snapshot(project)
    if (result.returncode != 2 or 'Unresolved upgrade conflicts prevent applying the plan' not in result.stdout
            or before != after):
        raise ValueError('Blocked upgrade must reject apply and preserve the project')
    return {'status': 'manual_migration_required', 'upgradeApplied': False,
            'blockingConflicts': blocking, 'projectUnchanged': True,
            'projectSha256': digest(json.dumps(before, sort_keys=True).encode())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', choices=tuple(BASELINE_COMMITS), required=True)
    parser.add_argument('--template', choices=('minimal', 'workbench'), required=True)
    parser.add_argument('--device', choices=('linux', 'macos'), required=True)
    parser.add_argument('--expect-manual-migration', action='store_true',
                        help='Verify v0.3 dependency conflicts and refusal without project changes; do not apply an upgrade')
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be outside the source checkout')
    output.mkdir(parents=True, exist_ok=False)
    old, project = output / 'old-source', output / 'project'
    old.mkdir()
    baseline_commit = BASELINE_COMMITS[args.baseline]
    summary = {'baseline': args.baseline, 'baselineCommit': baseline_commit,
               'template': args.template, 'device': args.device,
               'passed': False, 'steps': []}
    try:
        archive = output / 'baseline.tar'
        run(['git', 'archive', '--format=tar', '--output', str(archive), baseline_commit], source, output / 'archive.log')
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
        if args.expect_manual_migration:
            summary.update(verify_manual_migration(preview, old, project, source, initial,
                                                   output / 'rejected-apply.log'))
            summary['passed'] = True
            return finish(output, summary)
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
    return finish(output, summary)


def finish(output: Path, summary: dict) -> int:
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': summary['passed'], 'summary': str(output / 'summary.json')}))
    return 0 if summary['passed'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
