#!/usr/bin/env python3
"""Record source provenance for platform checks; it does not claim any checks passed."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

# `.gradle` is the Gradle project cache written during a release build.
# The wrapper under `gradle/` stays hashed.
IGNORED = {'.git', '.dart_tool', 'build', 'coverage', '.fvm', '__pycache__', '.DS_Store', 'generated',
           'ephemeral', 'Pods', '.symlinks', 'validation', 'research', '.gradle'}
ROOTS = ('blueprint.py', 'blueprint.json', '.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'DESIGN.md',
         'AGENTS.md', 'CLAUDE.md', 'README.md', 'MELOS_USAGE.md', 'CONTRIBUTING.md', 'LICENSE',
         'analysis_options.yaml', '.gitignore', 'Makefile', 'tool', 'scripts', '.agents',
         '.cursor', '.github', 'docs', 'examples', 'packages', 'apps', 'modules')
GENERATED_ENVIRONMENT_INPUTS = {('android', 'local.properties'), ('ios', 'Flutter', 'Generated.xcconfig')}


def source_manifest(root: Path) -> dict:
    files = {}
    for name in ROOTS:
        location = root / name
        candidates = [location] if location.is_file() else location.rglob('*')
        for path in candidates:
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(root)
            if (any(part in IGNORED for part in relative.parts)
                    or any(relative.parts[-len(parts):] == parts for parts in GENERATED_ENVIRONMENT_INPUTS)
                    or path.name.endswith(('.g.dart', '.freezed.dart', '.pyc'))
                    or path.name.startswith(('.flutter-plugins', 'GeneratedPluginRegistrant', 'generated_plugin_registrant', 'generated_plugins.cmake', 'flutter_export_environment'))):
                continue
            files[relative.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    encoded = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    try:
        commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, capture_output=True)
        commit_id = commit.stdout.strip() if commit.returncode == 0 else None
    except FileNotFoundError:
        commit_id = None
    return {'baseline_commit': commit_id,
            'source_sha256': hashlib.sha256(encoded).hexdigest(), 'files': dict(sorted(files.items()))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(source_manifest(args.root.resolve()), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
