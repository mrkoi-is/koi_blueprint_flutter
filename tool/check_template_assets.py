#!/usr/bin/env python3
"""Check real inherited AI assets after source-only material is removed; no SDK needed."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import re
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import blueprint
from tool.check_ai_assets import validate_assets


def check(root: Path) -> list[str]:
    previous = blueprint.ROOT
    try:
        return _check(root.resolve())
    finally:
        blueprint.ROOT = previous


def _check(root: Path) -> list[str]:
    blueprint.ROOT = root
    failures = []
    for template, example in blueprint.TEMPLATES.items():
        with tempfile.TemporaryDirectory(prefix='koi-template-assets-') as temporary:
            stage = Path(temporary)
            blueprint.inherit_workspace_assets(stage, 'template_probe')
            blueprint.copy(blueprint.source_root() / 'examples' / example, stage / 'apps/template_probe_app')
            for package in blueprint.REQUIRED_PACKAGES:
                blueprint.copy(blueprint.source_root() / 'packages' / package, stage / 'packages' / package)
            text = (root / 'pubspec.yaml').read_text(encoding='utf-8')
            text = re.sub(r'^workspace:\s*\n(?:[ \t].*\n|\n)*',
                          'workspace:\n  - apps/template_probe_app\n  - packages/koi_core\n  - packages/koi_ui\n\n', text, count=1, flags=re.M)
            (stage / 'pubspec.yaml').write_text(text, encoding='utf-8')
            (stage / 'README.md').write_text(blueprint.generated_readme('template_probe', template, ['web']), encoding='utf-8')
            failures.extend(f'{template}: {issue.rule} {issue.path}: {issue.message}' for issue in validate_assets(stage))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    failures = check(args.root)
    for failure in failures:
        print(failure, file=sys.stderr)
    if not failures:
        print('Template AI assets passed: minimal and workbench; source history excluded.')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
