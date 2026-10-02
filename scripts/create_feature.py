#!/usr/bin/env python3
"""Compatibility entry: new features are complete tested source templates."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from blueprint import main
if __name__ == '__main__':
    arguments = sys.argv[1:]
    presentation = '--presentation-only' in arguments
    if presentation:
        arguments.remove('--presentation-only')
    explicit_kind = any(value == '--kind' or value.startswith('--kind=') for value in arguments)
    if presentation and explicit_kind:
        print('create_feature: use --presentation-only or --kind, not both; no files were changed', file=sys.stderr)
        raise SystemExit(2)
    if not explicit_kind:
        arguments.extend(['--kind', 'presentation' if presentation else 'api'])
    raise SystemExit(main(['feature', *arguments]))
