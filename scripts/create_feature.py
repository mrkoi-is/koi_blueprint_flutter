#!/usr/bin/env python3
from pathlib import Path
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
    if len(sys.argv) != 3:
        print('用法: python scripts/create_feature.py <app_path> <feature_name>')
        return 1

    app_path = Path(sys.argv[1]).resolve()
    feature_name = sys.argv[2].strip()
    feature_root = app_path / 'lib' / 'features' / feature_name

    for directory in TEMPLATE_DIRS:
        path = feature_root / directory
        path.mkdir(parents=True, exist_ok=True)
        marker = path / '.gitkeep'
        marker.write_text('')

    print(f'已创建 Feature: {feature_root}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
