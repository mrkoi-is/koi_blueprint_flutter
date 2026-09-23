#!/usr/bin/env python3
from pathlib import Path
import re
import sys

TEMPLATE_DIRS = [
    'data/datasources',
    'data/repositories',
    'domain/entities',
    'domain/repositories',
    'presentation/providers',
    'presentation/screens',
    'presentation/widgets',
]


def main() -> int:
    if len(sys.argv) not in (3, 4) or (
        len(sys.argv) == 4 and sys.argv[3] != '--presentation-only'
    ):
        print('用法: python scripts/create_feature.py <app_path> <feature_name> [--presentation-only]')
        return 1

    app_path = Path(sys.argv[1]).resolve()
    feature_name = sys.argv[2].strip()
    if not app_path.is_dir() or not (app_path / 'pubspec.yaml').is_file():
        print(f'App 路径无效：{app_path}', file=sys.stderr)
        return 2
    if not re.fullmatch(r'[a-z][a-z0-9]*(?:_[a-z0-9]+)*', feature_name):
        print('Feature 名称必须是非空、单段 snake_case', file=sys.stderr)
        return 2

    features_root = app_path / 'lib' / 'features'
    feature_root = (features_root / feature_name).resolve()
    if not features_root.resolve().is_relative_to(app_path) or feature_root.parent != features_root.resolve():
        print('Feature 目录必须位于 App 的 lib/features 下', file=sys.stderr)
        return 2

    directories = (
        [directory for directory in TEMPLATE_DIRS if directory.startswith('presentation/')]
        if len(sys.argv) == 4 else TEMPLATE_DIRS
    )
    for directory in directories:
        path = feature_root / directory
        path.mkdir(parents=True, exist_ok=True)
        marker = path / '.gitkeep'
        marker.write_text('')

    print(f'已创建 Feature: {feature_root}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
