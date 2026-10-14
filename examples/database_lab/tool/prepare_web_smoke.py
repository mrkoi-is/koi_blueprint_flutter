#!/usr/bin/env python3
"""Verify pinned assets and prepare a local, deterministic browser test host."""
import hashlib
import json
from pathlib import Path
import shutil

app = Path(__file__).resolve().parents[1]
output = app / 'build' / 'web-smoke'
output.mkdir(parents=True, exist_ok=True)
manifest = json.loads((app / 'web' / 'drift-assets.json').read_text())
for asset in manifest['assets']:
    source = app / 'web' / asset['path']
    if hashlib.sha256(source.read_bytes()).hexdigest() != asset['sha256']:
        raise SystemExit(f"Asset checksum mismatch: {source}")
    shutil.copyfile(source, output / asset['path'])
shutil.copyfile(app / 'test' / 'fixtures' / 'library_v1.sqlite', output / 'library_v1.sqlite')
(output / 'index.html').write_text('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Database smoke</title></head><body>Running…<script src="database_smoke.js"></script></body></html>')
print(output)
