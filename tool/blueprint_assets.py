"""Deterministic typed asset paths with collision and ownership checks."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from tool.blueprint_capabilities import FileTransaction, safe_file


def file_hash(data):
    return hashlib.sha256(data).hexdigest()


def owned_changes(app, outputs, manifest_name, inputs, *, adopt=()):
    """Do not replace user edits; initial adoption must name exact owned paths."""
    app = Path(app).resolve()
    receipt_path = safe_file(app, manifest_name)
    previous = json.loads(receipt_path.read_text()) if receipt_path.is_file() else {'schema': 1, 'outputs': {}}
    if previous.get('schema') != 1:
        raise ValueError('Unknown generated asset manifest schema')
    changes = {}
    for relative, data in outputs.items():
        path = safe_file(app, relative)
        current = path.read_bytes() if path.is_file() else None
        if current == data:
            continue
        old = previous.get('outputs', {}).get(relative)
        if current is not None and file_hash(current) != old and relative not in adopt:
            raise ValueError(f'Generated asset conflicts with a local edit: {relative}')
        changes[relative] = data
    removed = previous.get('outputs', {}).keys() - outputs.keys()
    if removed:
        raise ValueError('Previously generated paths were removed; review them before regeneration: ' + ', '.join(sorted(removed)))
    receipt = {'schema': 1, 'inputs': inputs, 'outputs': {key: file_hash(data) for key, data in sorted(outputs.items())}}
    content = (json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    if not receipt_path.exists() or receipt_path.read_bytes() != content:
        changes[manifest_name] = content
    return changes


def declared_assets(app):
    app = Path(app).resolve()
    spec = (app / 'pubspec.yaml').read_text(encoding='utf-8')
    lines = spec.splitlines()
    assets = []
    in_flutter = False
    in_assets = False
    for line in lines:
        if line and not line[0].isspace() and not line.startswith('#'):
            in_flutter = line == 'flutter:'
            in_assets = False
        if not in_flutter:
            continue
        if re.match(r'^  assets:\s*(?:#.*)?$', line):
            in_assets = True
            continue
        if in_assets:
            if re.match(r'^  \S', line) or (line.strip() and not line.startswith('    ')):
                in_assets = False
                continue
            if not line.strip() or line.strip().startswith('#'):
                continue
            match = re.fullmatch(r'    - (.+?)\s*', line)
            if not match:
                raise ValueError('Typed assets require one relative string per indented assets list entry')
            value = match[1].strip()
            if value.startswith(('"', "'")):
                if value[-1] != value[0]:
                    raise ValueError('Invalid quoted asset path')
                value = value[1:-1]
            elif ' #' in value:
                value = value.split(' #', 1)[0].rstrip()
            path = safe_file(app, value)
            if not path.exists():
                raise ValueError(f'Missing declared asset: {value}')
            if value.endswith('/'):
                if not path.is_dir():
                    raise ValueError('Asset directory declaration points to a file')
                # Flutter directory entries include direct files, not subdirectories.
                candidates = sorted(p for p in path.iterdir() if p.is_file())
            elif path.is_file():
                candidates = [path]
            else:
                raise ValueError('Asset directories must end in /')
            for item in candidates:
                relative = item.relative_to(app).as_posix()
                safe_file(app, relative)
                if "'" in relative or '$' in relative or '\n' in relative or '\\' in relative:
                    raise ValueError('Unsupported character in asset path')
                assets.append(relative)
    if len(assets) != len(set(assets)):
        raise ValueError('Duplicate asset declarations')
    return sorted(assets)


def asset_plan(app):
    app = Path(app).resolve()
    paths = declared_assets(app)
    identifiers = {}
    folded = set()
    for relative in paths:
        words = re.findall(r'[A-Za-z0-9]+', relative)
        if not words:
            raise ValueError(f'Asset needs an ASCII identifier: {relative}')
        name = words[0].lower() + ''.join(word[:1].upper() + word[1:] for word in words[1:])
        if name in {'class', 'static', 'const', 'final', 'var', 'void', 'return', 'if', 'else', 'new', 'switch', 'case', 'default', 'for', 'while', 'do', 'is', 'as', 'with', 'extends', 'implements', 'enum', 'true', 'false', 'null', 'super', 'this', 'try', 'catch', 'throw', 'break', 'continue', 'assert', 'in', 'rethrow', 'all', 'bundleKey', 'expectedByteLengths'}:
            name = 'asset' + name[0].upper() + name[1:]
        if name[0].isdigit():
            name = 'asset' + name
        if name in identifiers or relative.casefold() in folded:
            raise ValueError(f'Case or generated-name collision: {relative}')
        identifiers[name] = relative
        folded.add(relative.casefold())
    dart = '// Generated by blueprint typed-assets. Do not edit.\nabstract final class AppAssets {\n'
    for name, relative in sorted(identifiers.items()):
        line = f"  static const String {name} = '{relative}';"
        if len(f'  static const String {name} =') > 80:
            line = f"  static const String\n  {name} =\n      '{relative}';"
        elif len(line) > 80:
            line = f"  static const String {name} =\n      '{relative}';"
        dart += line + '\n'
    dart += ('\n' if identifiers else '') + '  static const List<String> all = <String>['
    if identifiers:
        dart += '\n' + ''.join(f'    {name},\n' for name in sorted(identifiers)) + '  '
    dart += '];\n'
    dart += '\n  static const Map<String, int> expectedByteLengths = <String, int>{'
    if identifiers:
        dart += '\n'
        for name, relative in sorted(identifiers.items()):
            size = (app / relative).stat().st_size
            line = f'    {name}: {size},'
            dart += (line if len(line) <= 80 else f'    {name}:\n        {size},') + '\n'
        dart += '  '
    dart += '};\n'
    dart += '''
  /// Flutter bundle key when this asset is consumed from another package.
  static String bundleKey(String asset, {String? package}) {
    if (package == null) return asset;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(package)) {
      throw ArgumentError.value(package, 'package', 'Invalid package name');
    }
    return 'packages/$package/$asset';
  }
}
'''
    spec = (app / 'pubspec.yaml').read_text(encoding='utf-8')
    package_match = re.search(r'^name:\s*([a-z][a-z0-9_]*)\s*(?:#.*)?$', spec, re.M)
    if package_match is None:
        raise ValueError('Typed assets require a valid package name in pubspec.yaml')
    outputs = {'lib/shared/assets/app_assets.dart': b"// Generated by blueprint typed-assets. Do not edit.\nexport 'generated/app_assets.dart';\n",
               'lib/shared/assets/generated/app_assets.dart': dart.encode(),
               'test/typed_assets_test.dart': asset_loading_test(package_match[1]).encode()}
    inputs = {path: file_hash((app / path).read_bytes()) for path in paths}
    inputs['pubspec.yaml'] = file_hash(spec.encode())
    return owned_changes(app, outputs, '.blueprint/assets.json', inputs)


def asset_loading_test(package_name):
    """A real bundle/codec consumer; no mock asset channel or optional dependency."""
    return '''// Generated by blueprint typed-assets. Do not edit.
// Flutter's Chrome unit-test server does not serve the asset bundle.
// Verify Web assets in a built/running app; this test reads the real VM bundle.
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:''' + package_name + '''/shared/assets/app_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('typed bundle keys preserve local and package namespaces', () {
    const path = 'assets/example';
    expect(AppAssets.bundleKey(path), path);
    expect(
      AppAssets.bundleKey(path, package: 'shared_assets'),
      'packages/shared_assets/assets/example',
    );
    expect(
      () => AppAssets.bundleKey(path, package: '../invalid'),
      throwsArgumentError,
    );
  });
  if (AppAssets.all.isEmpty) {
    test(
      'typed asset loading requires declared assets',
      () {},
      skip: 'No assets declared; no bundle loading was verified.',
    );
    return;
  }
  for (final asset in AppAssets.all) {
    test('typed asset loads: $asset', () async {
      final data = await rootBundle.load(AppAssets.bundleKey(asset));
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, AppAssets.expectedByteLengths[asset], reason: asset);
      final extension = asset.split('.').last.toLowerCase();
      if (const {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(extension)) {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, greaterThan(0), reason: asset);
            expect(frame.image.height, greaterThan(0), reason: asset);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    });
  }
}
'''


def generate_assets(app):
    changes = asset_plan(app)
    if changes:
        FileTransaction(app, changes).commit()
    return {'schema': 1, 'status': 'PASS', 'changed': sorted(changes), 'assets': declared_assets(app)}
