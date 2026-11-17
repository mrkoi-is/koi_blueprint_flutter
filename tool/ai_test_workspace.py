"""Identify the workspace whose required AI test suites will be run."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path, PurePosixPath


def inspect_workspace(root: Path) -> tuple[str, str | None]:
    root = root.resolve()
    metadata = root / 'blueprint.json'
    if not metadata.exists():
        for relative in ('examples/ui_lab', 'examples/workbench_app'):
            if not (root / relative).is_dir():
                raise ValueError(f'Not a blueprint source workspace: missing {relative}')
        return 'source', None
    data = json.loads(metadata.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or data.get('schema') != 2:
        raise ValueError('A generated workspace requires schema 2 provenance')
    kind, member = data.get('template'), data.get('app')
    if kind not in ('minimal', 'workbench') or not isinstance(member, str):
        raise ValueError('Invalid workspace template or app metadata')
    path = PurePosixPath(member)
    if (not re.fullmatch(r'apps/[a-z][a-z0-9_]*', member) or path.is_absolute() or '..' in path.parts
            or str(path) != member or member == '.' or not (root / member).is_dir()
            or not (root / member).resolve().is_relative_to(root)):
        raise ValueError('Invalid or missing workspace app member')
    return kind, member


def platforms_for_host(root: Path, host: str) -> list[str]:
    kind, _ = inspect_workspace(root)
    if kind == 'source':
        raise ValueError('Source workspace has no generated platform selection')
    data = json.loads((root / 'blueprint.json').read_text(encoding='utf-8'))
    selected = data.get('platforms')
    supported = {'web', 'android', 'linux', 'ios', 'macos', 'windows'}
    if (not isinstance(selected, list) or not selected or
            any(not isinstance(item, str) or item not in supported for item in selected) or
            len(set(selected)) != len(selected)):
        raise ValueError('Invalid generated platform selection')
    hosts = {'Linux': ('web', 'android', 'linux'), 'macOS': ('ios', 'macos'),
             'Windows': ('windows',)}
    if host not in hosts:
        raise ValueError('Unknown runner OS')
    return [item for item in hosts[host] if item in selected]


def resolve_workbench_member(root: Path, requested: str | None = None) -> str:
    kind, app = inspect_workspace(root)
    if kind == 'minimal':
        raise ValueError('Workbench suite is unavailable in a minimal workspace')
    return requested or (app if kind == 'workbench' else 'examples/workbench_app')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--github-output', type=Path)
    parser.add_argument('--host', choices=('Linux', 'macOS', 'Windows'))
    args = parser.parse_args()
    kind, member = inspect_workspace(args.workspace)
    result = {'kind': kind, 'member': member or ''}
    if args.host:
        result['platforms'] = ','.join(platforms_for_host(args.workspace, args.host))
    if args.github_output:
        with args.github_output.open('a', encoding='utf-8') as output:
            for key, value in result.items():
                output.write(f'{key}={value}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
