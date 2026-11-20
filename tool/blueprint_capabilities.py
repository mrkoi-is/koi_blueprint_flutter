"""Explicit, transactional installation of tested capability recipes."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import os
import re

from tool.blueprint_config import digest
from tool.blueprint_provenance import read_metadata


def catalog(source):
    path = Path(source) / 'tool/capabilities/catalog.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema') != 1:
        raise ValueError('Unknown capability catalog schema')
    values = {item['id']: item for item in data['capabilities']}
    if len(values) != len(data['capabilities']):
        raise ValueError('Duplicate capability IDs')
    return values


def resolve(selected, entries):
    visiting, complete, ordered = set(), set(), []
    def visit(key):
        if key in complete:
            return
        if key in visiting:
            raise ValueError(f'Capability dependency cycle at {key}')
        if key not in entries:
            raise ValueError(f'Unknown capability: {key}')
        visiting.add(key)
        for dependency in entries[key].get('dependencies', []):
            visit(dependency)
        visiting.remove(key)
        complete.add(key)
        ordered.append(key)
    for key in selected:
        visit(key)
    return ordered


def safe_file(root, relative):
    relative = Path(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError(f'Invalid recipe path: {relative}')
    candidate = root / relative
    for current in (candidate, *candidate.parents):
        if current == root.parent:
            break
        if current.is_symlink():
            raise ValueError(f'Refusing symlink in recipe target: {current}')
    if not candidate.resolve().is_relative_to(root.resolve()):
        raise ValueError('Recipe target escapes workspace')
    return candidate


def atomic_write(path, data, *, new_file_mode=None):
    fd, name = tempfile.mkstemp(prefix='.blueprint-write-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists():
            os.chmod(name, path.stat().st_mode)
        elif new_file_mode is not None:
            os.chmod(name, new_file_mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def snapshot_install_inputs(root, app):
    """Hash existing app inputs before planning so later edits cannot be adopted."""
    root, app = Path(root).resolve(), Path(app).resolve()
    if not app.is_relative_to(root):
        raise ValueError('App must belong to destination workspace')
    ignored = {'.dart_tool', 'build', 'coverage', '.git', 'Pods', 'ephemeral', '.symlinks'}
    paths = [root / 'blueprint.json', root / 'pubspec.lock', root / 'pubspec.yaml']
    paths.extend(path for path in app.rglob('*')
                 if not any(part in ignored for part in path.relative_to(app).parts) and path.is_file())
    snapshot = {}
    for path in paths:
        relative = path.relative_to(root).as_posix()
        safe_file(root, relative)
        snapshot[relative] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    return snapshot


class FileTransaction:
    """Compare-before-write and rollback only bytes still owned by this operation."""
    def __init__(self, root, changes, *, expected_hashes=None, watch=()):
        self.root = Path(root).resolve()
        self.changes = changes
        self.before = {}
        for relative in dict.fromkeys((*changes, *watch)):
            path = safe_file(self.root, relative)
            self.before[relative] = path.read_bytes() if path.is_file() else None
            if expected_hashes is not None:
                observed = hashlib.sha256(self.before[relative]).hexdigest() if self.before[relative] is not None else None
                if observed != expected_hashes.get(relative):
                    raise ValueError(f'File changed while planning installation: {relative}')

    def commit(self, after_write=None):
        written, created = [], []
        # A separate lock avoids overwriting another installer's transaction journal.
        lock = self.root / '.blueprint-install.lock'
        try:
            descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError as error:
            raise ValueError('A capability transaction is active; inspect .blueprint-install.lock before recovery') from error
        try:
            with os.fdopen(descriptor, 'w') as output:
                json.dump({'pid': os.getpid(), 'files': list(self.changes)}, output)
            for relative, original in self.before.items():
                path = safe_file(self.root, relative)
                if (path.read_bytes() if path.is_file() else None) != original:
                    raise ValueError(f'File changed while planning installation: {relative}')
            for relative, content in self.changes.items():
                path = safe_file(self.root, relative)
                if (path.read_bytes() if path.is_file() else None) != self.before[relative]:
                    raise ValueError(f'Concurrent modification: {relative}')
                missing, directory = [], path.parent
                while not directory.exists():
                    missing.append(directory)
                    directory = directory.parent
                for directory in reversed(missing):
                    directory.mkdir()
                    created.append(directory)
                atomic_write(path, content)
                written.append(relative)
            if after_write:
                after_write()
        except Exception:
            for relative in reversed(written):
                path = self.root / relative
                # Never undo a user's concurrent edit, even on failed validation.
                if path.is_file() and path.read_bytes() == self.changes[relative]:
                    if self.before[relative] is None:
                        path.unlink()
                    else:
                        atomic_write(path, self.before[relative])
            for directory in reversed(created):
                if directory.exists() and not any(directory.iterdir()):
                    directory.rmdir()
            raise
        finally:
            lock.unlink(missing_ok=True)


def recipe_source(source, relative):
    direct = safe_file(source, relative)
    if direct.exists():
        return direct
    reference = safe_file(source / '.blueprint/reference', relative)
    if reference.exists():
        return reference
    raise ValueError(f'Missing capability source: {relative}')


def with_assets(spec, paths):
    """Only change the owned, explicit Flutter assets list; preserve other fields."""
    if not paths:
        return spec
    from blueprint import section
    block = section(spec, 'flutter')
    if not block:
        return spec.rstrip() + '\n\nflutter:\n  assets:\n' + ''.join(f'    - {p}\n' for p in paths)
    content = spec[block[1]:block[2]]
    asset_match = re.search(r'^  assets:\s*\n((?:    .*\n|\n)*)', content, re.M)
    if asset_match:
        additions = ''.join(f'    - {p}\n' for p in paths if f'    - {p}\n' not in asset_match[0])
        content = content[:asset_match.end()] + additions + content[asset_match.end():]
    else:
        content = content.rstrip() + '\n  assets:\n' + ''.join(f'    - {p}\n' for p in paths) + '\n'
    return spec[:block[1]] + content + spec[block[2]:]


def read_arb(content, locale, path):
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate ARB key in {path}: {key}')
            result[key] = value
        return result

    try:
        data = json.loads(content, object_pairs_hook=unique_keys)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f'Invalid ARB in {path}: {error}') from error
    if not isinstance(data, dict) or data.get('@@locale') != locale:
        raise ValueError(f'Expected ARB locale {locale} in {path}')
    return data


def arb_baseline(root, sha, path, *, old_source=None, source=None):
    if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{64}', sha):
        raise ValueError(f'Invalid ARB baseline digest: {path}')
    blob = safe_file(root, f'.blueprint/baseline/{sha}')
    if blob.is_file():
        content = blob.read_bytes()
        if hashlib.sha256(content).hexdigest() == sha:
            return content
        raise ValueError(f'Corrupt ARB baseline: {path}')
    # Older receipts recorded the recipe digest before installers kept a blob.
    if old_source:
        for workspace in dict.fromkeys((root, source or root)):
            for relative in (old_source, Path('.blueprint/reference') / old_source):
                candidate = safe_file(workspace, relative)
                if candidate.is_file():
                    content = candidate.read_bytes()
                    if hashlib.sha256(content).hexdigest() == sha:
                        return content
    raise ValueError(f'Missing verified ARB baseline: {path} ({sha})')


def same_arb_value(left, right):
    # JSON distinguishes true from 1, including inside placeholder metadata.
    return json.dumps(left, sort_keys=True) == json.dumps(right, sort_keys=True)


def merge_arb_keys(current, incoming, previous, app_base, path):
    merged = current.copy()
    for key, value in incoming.items():
        bases = previous.get(key, [app_base[key]] if key in app_base else [])
        if key in current:
            local = current[key]
            if same_arb_value(local, value) or (bases and all(same_arb_value(value, old) for old in bases)):
                continue
            if not bases or any(not same_arb_value(local, old) for old in bases):
                raise ValueError(f'Localization key conflicts: {path}: {key}')
        elif bases:
            raise ValueError(f'Localization key removed locally: {path}: {key}')
        merged[key] = value
    return merged


def plan_localizations(root, metadata, selected, source, changes, installed):
    """Compare all active owners of each key before writing its App locale."""
    previous_caps = metadata['capabilities']
    by_locale = {}
    for cap, recipe in selected.items():
        sources = recipe.get('localizationSources', {})
        if sources or 'localizations' in installed[cap]:
            installed[cap]['localizations'] = {}
        for locale, origin in sources.items():
            if locale not in ('en', 'zh', 'zh_Hant'):
                raise ValueError(f'Unsupported recipe locale: {locale}')
            by_locale.setdefault(locale, {})[cap] = origin

    for locale, sources in by_locale.items():
        relative = (Path(metadata['app']) / 'lib/l10n' / f'app_{locale}.arb').as_posix()
        target = safe_file(root, relative)
        if not target.is_file():
            raise ValueError(f'App-owned localization file is missing: {relative}')
        declared, incoming, previous = {}, {}, {}
        for cap, origin in sources.items():
            raw = recipe_source(source, origin).read_bytes()
            values = read_arb(raw, locale, origin)
            del values['@@locale']
            sha = hashlib.sha256(raw).hexdigest()
            record = {'source': origin, 'sourceSha256': sha}
            installed[cap]['localizations'][locale] = record
            prior = previous_caps.get(cap, {}).get('localizations', {}).get(locale)
            old = {}
            if prior:
                if prior.get('sourceSha256') == sha:
                    old = values
                else:
                    old_raw = arb_baseline(root, prior.get('sourceSha256'), relative,
                                           old_source=prior['source'], source=source)
                    old = read_arb(old_raw, locale, prior['source'])
                for key, value in old.items():
                    previous.setdefault(key, []).append(value)
            for key, value in values.items():
                if key in declared and not same_arb_value(declared[key], value):
                    raise ValueError(f'Localization key conflicts: {relative}: {key}')
                declared[key] = value
                if key not in old or not same_arb_value(old[key], value):
                    incoming[key] = value
            if prior != record:
                baseline = f'.blueprint/baseline/{sha}'
                blob = safe_file(root, baseline)
                if not blob.exists():
                    changes[baseline] = raw
                elif blob.read_bytes() != raw:
                    raise ValueError(f'Corrupt ARB baseline: {origin}')
        if not incoming:
            continue

        # Outside this request, installed recipes keep their recorded claims.
        for cap, capability in previous_caps.items():
            prior = capability.get('localizations', {}).get(locale)
            if cap in selected or not prior:
                continue
            raw = arb_baseline(root, prior.get('sourceSha256'), relative, old_source=prior['source'], source=source)
            claims = read_arb(raw, locale, prior['source'])
            for key in incoming:
                if key in claims:
                    if not same_arb_value(incoming[key], claims[key]):
                        raise ValueError(f'Localization key conflicts: {relative}: {key}')
                    previous.setdefault(key, []).append(claims[key])

        app_base = {}
        managed = metadata.get('managedFiles', {})
        if relative in managed:
            raw = arb_baseline(root, managed[relative].get('sha256'), relative)
            app_base = read_arb(raw, locale, relative)
        current = read_arb(target.read_bytes(), locale, relative)
        merged = merge_arb_keys(current, incoming, previous, app_base, relative)
        if not same_arb_value(current, merged):
            changes[relative] = (json.dumps(merged, ensure_ascii=False, indent=2) + '\n').encode()


def registry_content(package, ordered, entries):
    lines = ['// Managed by blueprint capability add. User entries belong in app_capabilities.dart.',
             f"import 'package:{package}/core/capabilities/app_capability.dart';",
             f"import 'package:{package}/core/capabilities/capability_lifecycle.dart';"]
    if any(entries[key].get('page', {}).get('titleKey') for key in ordered):
        lines.append(f"import 'package:{package}/l10n/generated/app_localizations.dart';")
    pages, starts, closers = [], [], []
    for key in sorted(ordered, key=lambda key: key != 'diagnostics'):
        entry, alias = entries[key], key.replace('-', '_')
        if page := entry.get('page'):
            lines.append(f"import 'package:{package}/{page['import']}' as {alias};")
            title_builder = ''
            if title_key := page.get('titleKey'):
                if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', title_key):
                    raise ValueError(f'Invalid localization key for {key}')
                title_builder = f', titleBuilder: (context) => AppLocalizations.of(context)!.{title_key}'
            pages.append(f"  AppCapabilityPage(id: '{key}', title: '{page['title']}', builder: {alias}.{page['builder']}{title_builder}),")
        for hook in ('initializer', 'prepareCloser', 'disposer'):
            if value := entry.get(hook):
                lines.append(f"import 'package:{package}/{value['import']}' as {alias}_{hook.lower()};")
        if initializer := entry.get('initializer'):
            starts.append(f"    await {alias}_initializer.{initializer['function']}();")
        if disposer := entry.get('disposer'):
            starts.append(f"    _ownedClosers.add({alias}_disposer.{disposer['function']});")
        if closer := entry.get('prepareCloser'):
            closers.append(f"  if (!await {alias}_preparecloser.{closer['function']}()) {{ return false; }}")
    lines += ['', 'final installedCapabilities = <AppCapabilityPage>[', *pages, '];', '']
    # Owners enter the cleanup stack only once; a failed bootstrap unwinds every
    # successfully acquired resource before the user can retry initialization.
    if starts:
        lines += ['bool _initialized = false;', 'Future<void>? _initializing;', 'final _ownedClosers = <Future<void> Function()>[];', '',
                  'Future<void> initializeInstalledCapabilities() {', '  if (_initialized) { return Future<void>.value(); }', '  return _initializing ??= Future<void>.sync(_initialize).whenComplete(() => _initializing = null);', '}', '',
                  'Future<void> _initialize() async {', '  if (_initialized) { return; }', '  try {', *starts,
                  '    _initialized = true;', '  } catch (error, trace) {',
                  '    try { await disposeInstalledCapabilities(); } catch (_) { /* Preserve the initialization failure. */ }',
                  '    Error.throwWithStackTrace(error, trace);', '  }', '}', '']
    else:
        lines += ['Future<void> initializeInstalledCapabilities() async {}', '']
    lines += ['Future<bool> prepareInstalledCapabilities() async {', *closers, '  return CapabilityLifecycle.instance.prepare();', '}', '']
    if starts:
        lines += ['Future<void> disposeInstalledCapabilities() async {', '  _initialized = false;',
                  '  final failures = <Object>[];', '  try { await CapabilityLifecycle.instance.close(); } catch (error) { failures.add(error); }', '  while (_ownedClosers.isNotEmpty) {',
                  '    final close = _ownedClosers.removeLast();', '    try { await close(); } catch (error) { failures.add(error); }',
                  '  }', "  if (failures.isNotEmpty) { throw StateError('Capability cleanup failed: $failures'); }", '}', '']
    else:
        lines += ['Future<void> disposeInstalledCapabilities() => CapabilityLifecycle.instance.close();', '']
    return '\n'.join(lines).encode()


def install_plan(root, app, selected, source, *, config=None, brand=None, brand_root=None, fresh=False):
    root, app, source = Path(root).resolve(), Path(app).resolve(), Path(source).resolve()
    if not app.is_relative_to(root):
        raise ValueError('App must belong to destination workspace')
    metadata = read_metadata(root)
    if not metadata or metadata['schema'] != 2:
        raise ValueError('Capability installation requires schema 2 composition hooks; run upgrade-report for a legacy project')
    if metadata['app'] != app.relative_to(root).as_posix():
        raise ValueError('Capability target differs from blueprint app identity')
    entries = catalog(source)
    ordered = resolve(selected, entries)
    receipt = json.loads(json.dumps(metadata))
    changes = {}
    app_relative = app.relative_to(root)
    spec_path = app / 'pubspec.yaml'
    spec = spec_path.read_text(encoding='utf-8')
    root_spec_path = root / 'pubspec.yaml'
    root_spec = root_spec_path.read_text(encoding='utf-8')
    package_match = re.search(r'^name:\s*(\w+)', spec, re.M)
    if not package_match:
        raise ValueError('App pubspec has no package name')
    package_name = package_match[1]
    installed = receipt['capabilities']
    all_preexisting = all(key in installed for key in ordered)
    for key in ordered:
        item = entries[key]
        if not item.get('recipe') and not item.get('providedByTemplate') and not item.get('tool'):
            raise ValueError(f'{key} is not an installable recipe yet')
        if metadata['template'] not in item.get('templates', ['minimal', 'workbench']):
            raise ValueError(f'{key} does not support template {metadata["template"]}')
        if not set(metadata['platforms']).intersection(item['platforms']):
            raise ValueError(f'{key} has no implementation for any selected platform')
        requested_config = (config or {}).get(key, {})
        allowed = {'appGroup'} if key == 'home-widget' else set()
        if not isinstance(requested_config, dict) or requested_config.keys() - allowed:
            raise ValueError(f'Unsupported {key} configuration fields')
        if key == 'branding':
            requested_config = brand or metadata.get('configuration', {}).get('brand', {})
        previous = installed.get(key)
        if previous:
            if previous['version'] != item['version'] or previous['configurationSha256'] != digest(requested_config):
                raise ValueError(f'{key} is already installed with another version/configuration; use upgrade-report')
            for relative, expected in previous['files'].items():
                path = safe_file(root, relative)
                if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError(f'Capability conflicts with existing user file: {relative}')
            continue
        files, origins = {}, {}
        sources = ([{'source': item['recipe'], 'destination': item.get('destination', '')}] if item.get('recipe') else []) + item.get('extraSources', [])
        for tree in sources:
            recipe = recipe_source(source, tree['source'])
            for file in ([recipe] if recipe.is_file() else sorted(recipe.rglob('*'))):
                if file.is_symlink():
                    raise ValueError('Recipe source must not contain symlinks')
                if not file.is_file() or file.name.endswith(('.g.dart', '.freezed.dart', '.pyc')) or any(part in ('.dart_tool', 'build', '__pycache__', 'generated') for part in file.parts):
                    continue
                suffix = Path() if recipe.is_file() else file.relative_to(recipe)
                relative = (app_relative / tree['destination'] / suffix).as_posix()
                content = file.read_bytes()
                if file.suffix == '.dart':
                    content = content.replace(b'__APP_PACKAGE__', package_name.encode())
                    if item.get('sourcePackage'):
                        content = content.replace(('package:' + item['sourcePackage'] + '/').encode(), ('package:' + package_name + '/').encode())
                target = safe_file(root, relative)
                if target.exists() or relative in changes:
                    raise ValueError(f'Capability conflicts with existing user file: {relative}')
                files[relative] = hashlib.sha256(content).hexdigest()
                origins[relative] = tree['source'] if recipe.is_file() else (Path(tree['source']) / suffix).as_posix()
                changes[relative] = content
        for package in item.get('packages', []):
            if not re.fullmatch(r'[a-z][a-z0-9_]*', package):
                raise ValueError(f'Invalid support package name: {package}')
            package_relative = Path('packages') / package
            package_target = safe_file(root, package_relative)
            registered = f'  - {package_relative.as_posix()}\n' in root_spec
            if package_target.exists() and not registered:
                raise ValueError(f'Unregistered support package conflicts with user files: {package_target}')
            if not package_target.exists():
                package_source = recipe_source(source, package_relative)
                if not package_source.is_dir() or not (package_source / 'pubspec.yaml').is_file():
                    raise ValueError(f'Missing support package source: {package}')
                for file in sorted(package_source.rglob('*')):
                    if file.is_symlink():
                        raise ValueError('Support package source must not contain symlinks')
                    if not file.is_file() or file.name.endswith(('.g.dart', '.freezed.dart', '.pyc')) or any(part in ('.dart_tool', 'build', '__pycache__', 'generated') for part in file.parts):
                        continue
                    relative = (package_relative / file.relative_to(package_source)).as_posix()
                    if relative in changes or safe_file(root, relative).exists():
                        raise ValueError(f'Support package conflicts with existing file: {relative}')
                    content = file.read_bytes()
                    changes[relative] = content
                    files[relative] = hashlib.sha256(content).hexdigest()
                    origins[relative] = relative
            if not registered:
                from blueprint import with_members
                root_spec = with_members(root_spec, [package_relative.as_posix()])
        installed[key] = {'version': item['version'], 'configurationSha256': digest(requested_config),
                          'configuration': requested_config, 'files': files, 'origins': origins,
                          'localizations': {}}
        for section_name, dep_field in [('dependencies', 'pubspecDependencies'), ('dev_dependencies', 'pubspecDevDependencies')]:
            dependencies = {**({name: 'any' for name in item.get('packages', [])} if section_name == 'dependencies' else {}),
                            **item.get(dep_field, {})}
            for name, constraint in dependencies.items():
                from blueprint import dependency_entries, section
                existing = dependency_entries(spec, section_name)
                if name not in existing:
                    other = 'dev_dependencies' if section_name == 'dependencies' else 'dependencies'
                    if name in dependency_entries(spec, other):
                        raise ValueError(f'{name} is already declared in {other}; resolve its role explicitly')
                    block = section(spec, section_name)
                    if block:
                        spec = spec[:block[2]].rstrip() + f'\n  {name}: {constraint}\n\n' + spec[block[2]:]
                    else:
                        spec = spec.rstrip() + f'\n\n{section_name}:\n  {name}: {constraint}\n'
        spec = with_assets(spec, item.get('assets', []))
    plan_localizations(root, metadata, {key: entries[key] for key in ordered}, source, changes, installed)
    # Native outputs share exactly the same outer transaction as Dart and Pub.
    for relative, expected in metadata.get('nativeFiles', {}).items():
        path = safe_file(root, relative)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Managed native wiring was changed: {relative}')
    from tool.platform_capabilities import plan_native_changes
    from tool.device_capabilities import plan_device_changes
    native_config = {key: item.get('configuration', {}) for key, item in installed.items()}
    native = plan_native_changes(app, installed, native_config)
    native.update(plan_device_changes(app, installed, native_config, base_changes=native))
    for relative, content in native.items():
        path = safe_file(app, relative)
        target = (app_relative / relative).as_posix()
        if not path.is_file() or path.read_bytes() != content:
            changes[target] = content
        receipt.setdefault('nativeFiles', {})[target] = hashlib.sha256(content).hexdigest()
        # The generated App Group constant replaces the recipe's default.
        for item in installed.values():
            if target in item['files']:
                item['files'][target] = hashlib.sha256(content).hexdigest()
    if 'branding' in installed and 'branding' not in metadata['capabilities']:
        from tool.blueprint_branding import apply_brand
        planned = apply_brand(app, installed['branding']['configuration'], metadata['platforms'], source_root=brand_root,
                              adopt_runner_assets=fresh, plan_only=True)
        for relative, content in planned.items():
            target = (app_relative / relative).as_posix()
            changes[target] = content
            installed['branding']['files'][target] = hashlib.sha256(content).hexdigest()
        spec = with_assets(spec, ['assets/brand/'])
    if spec.encode() != spec_path.read_bytes():
        changes[spec_path.relative_to(root).as_posix()] = spec.encode()
    if root_spec.encode() != root_spec_path.read_bytes():
        changes['pubspec.yaml'] = root_spec.encode()
    # Asset paths must see pending branding and recipe outputs, without mutating
    # the destination during dry-run. This small app stage also avoids Pub calls.
    if 'typed-assets' in installed and ('typed-assets' not in metadata['capabilities'] or changes):
        import shutil
        from tool.blueprint_assets import asset_plan
        with tempfile.TemporaryDirectory(prefix='blueprint-assets-plan-') as temporary:
            stage = Path(temporary)
            shutil.copytree(app, stage, dirs_exist_ok=True, ignore=shutil.ignore_patterns('.dart_tool', 'build', 'Pods', 'ephemeral', '.symlinks'), symlinks=True)
            for relative, content in changes.items():
                path = Path(relative)
                if path.is_relative_to(app_relative):
                    target = stage / path.relative_to(app_relative)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(content)
            for relative, content in asset_plan(stage).items():
                target = (app_relative / relative).as_posix()
                changes[target] = content
                installed['typed-assets']['files'][target] = hashlib.sha256(content).hexdigest()
    registration = app_relative / 'lib/core/capabilities/installed_capabilities.dart'
    registration_path = safe_file(root, registration)
    if not registration_path.is_file():
        raise ValueError('Missing capability composition hook; review upgrade-report first')
    old_hash = metadata.get('registrySha256')
    if old_hash and hashlib.sha256(registration_path.read_bytes()).hexdigest() != old_hash:
        raise ValueError('Managed capability registry was modified; move custom entries to app_capabilities.dart')
    if not old_hash and metadata['capabilities']:
        raise ValueError('Installed capability registry has no baseline')
    if all_preexisting and not changes and receipt == metadata:
        return {'capabilities': ordered, 'files': [], 'changes': {}}
    if not all_preexisting:
        content = registry_content(package_name, resolve(sorted(installed), entries), entries)
        if content != registration_path.read_bytes():
            changes[registration.as_posix()] = content
        receipt['registrySha256'] = hashlib.sha256(content).hexdigest()
    receipt_content = (json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    if receipt_content != (root / 'blueprint.json').read_bytes():
        changes['blueprint.json'] = receipt_content
    return {'capabilities': ordered, 'files': list(changes), 'changes': changes}
