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
    raise SystemExit(main(['feature', *arguments, '--kind', 'presentation' if presentation else 'api']))
