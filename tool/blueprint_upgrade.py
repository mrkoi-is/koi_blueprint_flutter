"""Conservative, auditable upgrade planning and crash-recoverable file transactions.

The caller serializes plans outside the target project and holds workspace_lock
for apply/rollback. Unsupported dependency or reference changes block apply.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import os
import subprocess
import tempfile
import difflib
from contextlib import redirect_stdout
from io import StringIO
import uuid
from pathlib import Path, PureWindowsPath

from tool.blueprint_capabilities import atomic_write, safe_file
from tool.blueprint_provenance import read_metadata, resolve_app_package_name, source_identity


def _hash(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def _read(root, path):
    target = safe_file(root, path)
    if target.exists() and not target.is_file():
        raise ValueError(f'Not a regular file: {path}')
    return target.read_bytes() if target.is_file() else None


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()


def _seal(value):
    return _hash(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode())


def _render_app_test(raw, relative, metadata, blueprint, app_package):
    """Render template assets with the target App package and project branding."""
    path = Path(relative)
    if 'assets' in path.parts or path.suffix not in ('.dart', '.yaml', '.md', '.json', '.arb'):
        return raw
    template = metadata.get('template', 'minimal')
    template_name = blueprint.TEMPLATES[template]
    name = metadata['name']
    brand = metadata.get('configuration', {}).get('brand', {}).get('displayName')
    replacements = {
        template_name: app_package,
        blueprint.pascal(template_name): blueprint.pascal(name) + 'App',
        'Starter App' if template == 'minimal' else 'Koi Workbench': brand or blueprint.pascal(name),
        'Executable blueprint reference, also used by the generator': json.dumps(
            f'{brand or blueprint.pascal(name)} Flutter application', ensure_ascii=False),
    }
    if template == 'workbench':
        replacements.update({'Koi Workspace': brand or blueprint.pascal(name),
                             'Koi 工作区': brand or blueprint.pascal(name) + ' 工作区',
                             'Koi 工作區': brand or blueprint.pascal(name) + ' 工作區'})
    pattern = re.compile('|'.join(re.escape(value) for value in sorted(replacements, key=len, reverse=True)))
    return pattern.sub(lambda match: replacements[match[0]], raw.decode('utf-8')).encode('utf-8')



def _merge_supported_pubspec(baseline, local, target):
    """Merge only recognized upstream insertions while keeping local bytes/comments."""
    old, current, new = (value.decode('utf-8') for value in (baseline, local, target))
    material = '  uses-material-design: true\n'
    driver = '  flutter_driver:\n    sdk: flutter\n'
    stripped = new
    additions = []
    for token, name in ((material, 'material'), (driver, 'driver')):
        if token not in old and token in stripped:
            if stripped.count(token) != 1:
                raise ValueError('ambiguous upstream pubspec insertion')
            stripped = stripped.replace(token, '', 1)
            additions.append(name)
    if stripped != old:
        raise ValueError('unsupported upstream pubspec changes')
    lines = current.splitlines(keepends=True)
    if not current.endswith('\n'):
        raise ValueError('pubspec must end in newline')
    for name in additions:
        heading = 'flutter' if name == 'material' else 'dev_dependencies'
        indices = [i for i, line in enumerate(lines) if re.fullmatch(heading + r':\s*(?:#.*)?\n', line)]
        if len(indices) != 1:
            raise ValueError(f'ambiguous {heading} section')
        start = indices[0]
        end = start + 1
        while end < len(lines) and (not lines[end].strip() or lines[end].startswith((' ', '#'))):
            end += 1
        section = ''.join(lines[start + 1:end])
        key = 'uses-material-design' if name == 'material' else 'flutter_driver'
        present = re.findall(r'^  ' + re.escape(key) + r':[^\n]*$', section, re.M)
        if present:
            if name == 'material' and len(present) == 1 and re.fullmatch(r'  uses-material-design:\s*true\s*(?:#.*)?', present[0]):
                continue
            if name == 'driver' and len(present) == 1 and re.search(r'^  flutter_driver:\s*(?:#.*)?\n    sdk:\s*flutter\s*(?:#.*)?$', section, re.M):
                continue
            raise ValueError(f'conflicting local {key}')
        token = material if name == 'material' else driver
        lines.insert(start + 1, token)
    return ''.join(lines).encode('utf-8'), additions


def _dependency_snapshot(root):
    ignored = {'.git', '.blueprint', '.dart_tool', '.fvm', 'build', 'coverage', 'Pods',
               'ephemeral', '.symlinks', '.gradle', '__pycache__'}
    files = {}
    for directory, folders, names in os.walk(root, followlinks=False):
        folders[:] = [f for f in folders if f not in ignored and not (Path(directory) / f).is_symlink()]
        for name in names:
            if name not in ('pubspec.yaml', 'pubspec_overrides.yaml'):
                continue
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            data = _read(root, relative)
            files[relative] = data
    for name in ('pubspec.lock', '.fvmrc'):
        files[name] = _read(root, name)
    if files.get('pubspec.yaml') is None or files.get('pubspec.lock') is None or files.get('.fvmrc') is None:
        raise ValueError('Root pubspec, lockfile and pinned SDK are required')
    return files


def _check_dependency_paths(stage, relative, text, blueprint):
    """Accept explicit block dependencies only; never guess YAML aliases/maps."""
    # The generator already uses this constrained block-mapping grammar. A
    # quoted/complex top-level key could otherwise conceal a dependency section.
    seen_heading = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line.startswith((' ', '\t')):
            if not seen_heading:
                raise ValueError(f'Ambiguous dependency YAML: {relative}')
            continue
        if not re.match(r'^[A-Za-z_][A-Za-z0-9_-]*:', line):
            raise ValueError(f'Ambiguous dependency YAML: {relative}')
        seen_heading = True
    for section in ('dependencies', 'dev_dependencies', 'dependency_overrides'):
        try:
            entries = blueprint.dependency_entries(text, section)
        except blueprint.BlueprintError as error:
            raise ValueError(f'Ambiguous dependency YAML: {relative}: {error}') from error
        for entry in entries.values():
            lines = entry.splitlines()
            value = lines[0].split(':', 1)[1].strip().split('#', 1)[0].strip()
            nested = [line for line in lines[1:] if line.strip() and not line.lstrip().startswith('#')]
            if value:
                if value.startswith(('{', '[', '*', '&', '!', '|', '>')) or nested:
                    raise ValueError(f'Ambiguous dependency YAML: {relative}')
                continue
            fields = {}
            last_field = None
            for line in nested:
                match = re.fullmatch(r'    ([a-z][a-z0-9_]*):[ \t]*(.*)', line)
                if match:
                    key, value = match.groups()
                    if key in fields or key not in ('path', 'sdk', 'git', 'hosted', 'version'):
                        raise ValueError(f'Ambiguous dependency YAML: {relative}')
                    fields[key] = value
                    last_field = key
                elif not line.startswith('      ') or last_field not in ('git', 'hosted'):
                    raise ValueError(f'Ambiguous dependency YAML: {relative}')
            if 'path' not in fields:
                continue
            value = fields['path'].split(' #', 1)[0].strip()
            if value.startswith('"'):
                try:
                    value = json.loads(value)
                except ValueError as error:
                    raise ValueError(f'Ambiguous local path dependency: {relative}') from error
            elif value.startswith("'") and len(value) >= 2 and value[-1] == "'":
                value = value[1:-1]
            if not re.fullmatch(r'[A-Za-z0-9_./\\-]+', value):
                raise ValueError(f'Ambiguous local path dependency: {relative}')
            dep = Path(value.replace('\\', '/'))
            if dep.is_absolute() or PureWindowsPath(value).anchor:
                raise ValueError(f'External local path dependency: {relative}')
            candidate = (stage / relative).parent / dep
            if not candidate.resolve().is_relative_to(stage.resolve()):
                raise ValueError(f'External local path dependency: {relative}')


def _resolve_dependencies(root, updates, blueprint):
    """Resolve dependencies in an isolated workspace; return reviewed lock delta."""
    snapshot = _dependency_snapshot(root)
    with redirect_stdout(StringIO()):
        sdk = blueprint.SDK(root)
    with tempfile.TemporaryDirectory(prefix='koi-upgrade-pub-') as temporary:
        stage = Path(temporary)
        for relative, data in snapshot.items():
            if data is None:
                continue
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(updates.get(relative, data))
        # Never let a staged pubspec point back into a real project or another
        # directory outside the temporary workspace. Ambiguous YAML is blocked.
        for relative, original in snapshot.items():
            if not relative.endswith(('pubspec.yaml', 'pubspec_overrides.yaml')) or original is None:
                continue
            _check_dependency_paths(stage, relative, updates.get(relative, original).decode('utf-8'), blueprint)
        try:
            result = subprocess.run([str(sdk.flutter), 'pub', 'get'], cwd=stage,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ValueError(f'Dependency resolution failed: {error}') from error
        if result.returncode:
            raise ValueError('Dependency resolution failed: ' + result.stderr[-2000:])
        locked = (stage / 'pubspec.lock').read_bytes()
    if _dependency_snapshot(root) != snapshot:
        raise ValueError('Dependency inputs changed during planning')
    previous = snapshot['pubspec.lock']
    diff = ''.join(difflib.unified_diff(previous.decode('utf-8').splitlines(keepends=True),
                                       locked.decode('utf-8').splitlines(keepends=True),
                                       fromfile='pubspec.lock (before)', tofile='pubspec.lock (after)'))
    return locked, {path: _hash(data) for path, data in sorted(snapshot.items())}, diff, {
        'command': ['flutter', 'pub', 'get'], 'flutter': str(sdk.flutter),
        'flutterVersion': blueprint.pinned_flutter_version(root)}


def _format_app_pair(root, metadata, old, new, blueprint):
    """Render two app files with the target project's pinned SDK and language config."""
    config = _read(root, '.dart_tool/package_config.json')
    app = metadata['app']
    app_spec = _read(root, app + '/pubspec.yaml')
    root_spec = _read(root, 'pubspec.yaml')
    if not config or not app_spec or not root_spec:
        raise ValueError('Prepared workspace package configuration is required')
    with redirect_stdout(StringIO()):
        sdk = blueprint.SDK(root)
    with tempfile.TemporaryDirectory(prefix='koi-upgrade-format-') as temporary:
        stage = Path(temporary)
        for name, data in (('.dart_tool/package_config.json', config),
                           (app + '/pubspec.yaml', app_spec), ('pubspec.yaml', root_spec)):
            path = stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        files = []
        for label, data in (('old', old), ('new', new)):
            file = stage / app / 'lib' / ('koi_upgrade_' + label + '.dart')
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            files.append(file)
        result = subprocess.run([str(sdk.dart), 'format', *map(str, files)], cwd=stage,
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        if result.returncode:
            raise ValueError('Dart formatting failed: ' + result.stderr[-1000:])
        result_bytes = [file.read_bytes() for file in files]
    if (_read(root, '.dart_tool/package_config.json') != config or
            _read(root, app + '/pubspec.yaml') != app_spec or _read(root, 'pubspec.yaml') != root_spec):
        raise ValueError('Formatter inputs changed during planning')
    return *result_bytes, {'sdk': str(sdk.dart), 'packageConfigSha256': _hash(config),
                           'appPubspecSha256': _hash(app_spec), 'rootPubspecSha256': _hash(root_spec)}

def plan(root, source, resolutions=None):
    """Return a JSON-serializable plan; never write to root or source.

    resolutions is a dict path -> {"choice": "keep-local"|"merged",
    "currentSha256": <sha256 or null>} for managed files, or
    {"choice": "take-upstream", "currentSha256": ..., "targetSha256": ...}
    for an unmanaged reference. Choices are bound to reviewed bytes.
    """
    import blueprint
    root, source = Path(root).resolve(), Path(source).resolve()
    if root == source or root.is_relative_to(source) or source.is_relative_to(root):
        raise ValueError('Source and destination must be separate workspaces')
    metadata = read_metadata(root)
    if (not metadata or metadata.get('schema') != 2 or
            not isinstance(metadata.get('managedFiles'), dict) or not metadata['managedFiles'] or
            not re.fullmatch(r'[0-9a-f]{64}', str(metadata.get('source', {}).get('sourceSha256', '')))):
        raise ValueError('A schema 2 project with trusted source and managed baselines is required')
    identity = source_identity(source)
    source_before = identity['sourceSha256']
    resolutions = resolutions or {}
    if not isinstance(resolutions, dict):
        raise ValueError('Resolutions must be an object')
    asset_entries = blueprint.workspace_asset_plan(source, metadata.get('name', 'project'),
        metadata.get('template', 'minimal'), metadata.get('platforms', ['web']))
    assets = {e['destination']: e for e in asset_entries if e['kind'] in ('guidance', 'tooling')}
    # Reference data was historically unmanaged; it cannot be overwritten safely.
    references = {e['destination']: e for e in asset_entries
                  if e['kind'] == 'reference' and 'generated' not in Path(e['destination']).parts}
    # Reuse the generator's checked reference inventory, including its ignore
    # rules, while selecting only active package assets and App test inputs.
    app = metadata.get('app', '')
    safe_file(root, app)
    template = metadata.get('template', 'minimal')
    template_name = blueprint.TEMPLATES.get(template)
    if not template_name or not app:
        raise ValueError('Unknown project template or app path')
    app_package = resolve_app_package_name(root, app)
    for entry in references.values():
        origin = entry['source']
        origin_path = Path(origin)
        if len(origin_path.parts) >= 3 and origin_path.parts[0] == 'packages':
            package = origin_path.parts[1]
            if package in blueprint.REQUIRED_PACKAGES and (root / 'packages' / package).is_dir():
                assets[origin] = {**entry, 'kind': 'package'}
        prefix = f'examples/{template_name}/'
        if origin.startswith(prefix):
            relative = origin[len(prefix):]
            if Path(relative).parts[0] in ('test', 'integration_test', 'test_driver'):
                assets[f'{app}/{relative}'] = {**entry, 'kind': 'app_test'}
            elif Path(relative).parts[0] == 'lib':
                assets[f'{app}/{relative}'] = {**entry, 'kind': 'app_new_lib'}
    app_pubspec_origin = f'examples/{template_name}/pubspec.yaml'
    if _read(source, app_pubspec_origin) is not None:
        assets[f'{app}/pubspec.yaml'] = {'source': app_pubspec_origin, 'kind': 'app_pubspec'}
    managed = metadata['managedFiles']
    # Only include already managed Dart business files; additions and removals
    # require separate review because they may alter application architecture.
    for path, entry in managed.items():
        origin = entry.get('source')
        if (isinstance(origin, str) and origin.startswith(f'examples/{template_name}/lib/')
                and path.startswith(app + '/lib/') and path.endswith('.dart')):
            assets[path] = {'source': origin, 'kind': 'app_dart'}
    for path, entry in managed.items():
        sha = entry.get('sha256')
        if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{64}', sha):
            raise ValueError(f'Invalid baseline digest: {path}')
        if _hash(_read(root, '.blueprint/baseline/' + sha)) != sha:
            raise ValueError(f'Missing or corrupt baseline: {path}')
        _read(root, path)  # enforce safe paths even when unchanged
    operations, conflicts, retained = [], [], []
    new_metadata = json.loads(json.dumps(metadata))
    baseline_blobs = {}
    used_resolutions = set()
    dependency_updates = {}
    dependency_changes = []
    formatter_evidence = []
    # Never guess transformations for App, packages, dependency or capability files.
    for path, entry in sorted(managed.items()):
        if path in assets or entry.get('source') is None:
            continue
        origin = entry.get('source')
        upstream = _read(source, origin)
        if upstream is None:
            upstream = _read(source, '.blueprint/reference/' + origin)
        old_source = entry.get('sourceSha256', entry['sha256'])
        if _hash(upstream) != old_source:
            conflicts.append({'path': path, 'reason': 'unsupported_managed_change',
                              'detail': 'App, package, capability and dependency changes require explicit migration.'})
    for path, entry in sorted(assets.items()):
        origin = entry['source']
        raw = _read(source, origin)
        if raw is None:
            raise ValueError(f'Source asset disappeared: {origin}')
        if entry['kind'] == 'app_dart':
            prior = managed[path]
            if _hash(raw) == prior.get('sourceSha256', prior['sha256']):
                retained.append({'path': path, 'reason': 'unchanged_or_local'})
                continue
            previous = _read(root, '.blueprint/reference/' + origin)
            if _hash(previous) != prior.get('sourceSha256'):
                conflicts.append({'path': path, 'reason': 'unsupported_managed_change',
                                  'detail': 'Original upstream bytes unavailable for reliable rendering.'})
                continue
            try:
                relative = Path(origin).relative_to('examples/' + template_name)
                old_render = _render_app_test(previous, relative, metadata, blueprint, app_package)
                new_render = _render_app_test(raw, relative, metadata, blueprint, app_package)
                formatted_old, new, evidence = _format_app_pair(root, metadata, old_render, new_render, blueprint)
                if _hash(formatted_old) != prior['sha256']:
                    raise ValueError('Original source cannot reproduce the trusted generated baseline')
                formatter_evidence.append({'path': path, **evidence})
            except (ValueError, OSError, subprocess.TimeoutExpired) as error:
                conflicts.append({'path': path, 'reason': 'unsupported_managed_change', 'detail': str(error)})
                continue
        elif entry['kind'] == 'app_new_lib':
            relative = Path(origin).relative_to('examples/' + template_name)
            new = _render_app_test(raw, relative, metadata, blueprint, app_package)
            if relative.suffix == '.dart':
                try:
                    _, new, evidence = _format_app_pair(root, metadata, new, new, blueprint)
                    formatter_evidence.append({'path': path, **evidence})
                except (ValueError, OSError, subprocess.TimeoutExpired) as error:
                    conflicts.append({'path': path, 'reason': 'unsupported_managed_change', 'detail': str(error)})
                    continue
        elif entry['kind'] in ('app_test', 'app_pubspec'):
            relative = Path(origin).relative_to('examples/' + template_name)
            new = _render_app_test(raw, relative, metadata, blueprint, app_package)
        elif entry['kind'] == 'package':
            new = raw
        else:
            new = blueprint.render_workspace_asset(raw, path, metadata.get('name', 'project'))
        current = _read(root, path)
        prior = managed.get(path)
        if path.endswith('/pubspec.yaml'):
            if prior is None or current is None:
                conflicts.append({'path': path, 'reason': 'dependency_resolution_required',
                                  'detail': 'Missing managed pubspec or trusted baseline.'})
                continue
            if _hash(raw) == prior.get('sourceSha256', prior['sha256']):
                retained.append({'path': path, 'reason': 'unchanged_or_local'})
                continue
            try:
                baseline = _read(root, '.blueprint/baseline/' + prior['sha256'])
                merged, additions = _merge_supported_pubspec(baseline, current, new)
            except (ValueError, UnicodeError) as error:
                conflicts.append({'path': path, 'reason': 'dependency_resolution_required', 'detail': str(error)})
                continue
            if merged != current:
                operations.append({'path': path, 'before': _hash(current), 'after': _hash(merged),
                                   'content': base64.b64encode(merged).decode()})
                dependency_updates[path] = merged
            dependency_changes.append({'path': path, 'additions': additions})
            sha = _hash(new)
            baseline_blobs['.blueprint/baseline/' + sha] = new
            new_metadata['managedFiles'][path] = {'sha256': sha, 'source': origin, 'sourceSha256': _hash(raw)}
            continue
        if prior:
            old = prior['sha256']
            source_old = prior.get('sourceSha256', old)
            changed_local = _hash(current) != old
            changed_upstream = _hash(raw) != source_old
            if not changed_upstream:
                retained.append({'path': path, 'reason': 'local_change' if changed_local else 'unchanged'})
                continue
            conflict = changed_local and current != new
        else:
            conflict = current is not None
        if conflict:
            choice = resolutions.get(path)
            if (not isinstance(choice, dict) or choice.get('choice') not in ('keep-local', 'merged')
                    or choice.get('currentSha256') != _hash(current)):
                conflicts.append({'path': path, 'reason': 'conflict' if prior else 'no_baseline',
                                  'currentSha256': _hash(current), 'targetSha256': _hash(new)})
                continue
            used_resolutions.add(path)
            retained.append({'path': path, 'reason': choice['choice'], 'sha256': _hash(current)})
        elif current != new:
            operation = {'path': path, 'before': _hash(current), 'after': _hash(new),
                         'content': base64.b64encode(new).decode()}
            if current is None:
                operation['newFileMode'] = safe_file(source, origin).stat().st_mode & 0o777
            operations.append(operation)
        sha = _hash(new)
        baseline_blobs['.blueprint/baseline/' + sha] = new
        new_metadata['managedFiles'][path] = {'sha256': sha, 'source': origin, 'sourceSha256': _hash(raw)}
    reference_baselines = new_metadata.setdefault('referenceFiles', {})
    for path in sorted(set(reference_baselines) - set(references)):
        conflicts.append({'path': path, 'reason': 'reference_deletion_unsupported'})
    for path, entry in sorted(references.items()):
        current = _read(root, path)
        target = _read(source, entry['source'])
        target_sha = _hash(target)
        prior = reference_baselines.get(path)
        if prior is not None:
            if (not isinstance(prior, str) or not re.fullmatch(r'[0-9a-f]{64}', prior)
                    or _hash(_read(root, '.blueprint/baseline/' + prior)) != prior):
                raise ValueError(f'Missing or corrupt reference baseline: {path}')
            if target_sha == prior:
                continue
            needs_review = _hash(current) != prior and current != target
        else:
            # Identical existing bytes need no change and never invent history.
            if current == target and current is not None:
                continue
            needs_review = current is not None
        if needs_review:
            choice = resolutions.get(path)
            if (not isinstance(choice, dict) or choice.get('choice') != 'take-upstream'
                    or choice.get('currentSha256') != _hash(current)
                    or choice.get('targetSha256') != target_sha):
                conflicts.append({'path': path, 'reason': 'unmanaged_reference' if prior is None else 'reference_conflict',
                                  'currentSha256': _hash(current), 'targetSha256': target_sha,
                                  'detail': 'Reference replacement requires explicit review.'})
                continue
            used_resolutions.add(path)
        if current != target:
            operation = {'path': path, 'before': _hash(current), 'after': target_sha,
                         'content': base64.b64encode(target).decode()}
            if current is None:
                operation['newFileMode'] = safe_file(source, entry['source']).stat().st_mode & 0o777
            operations.append(operation)
        reference_baselines[path] = target_sha
        baseline_blobs['.blueprint/baseline/' + target_sha] = target
    dependency_evidence = None
    if dependency_changes:
        try:
            lock, inputs, diff, resolver = _resolve_dependencies(root, dependency_updates, blueprint)
            dependency_evidence = {'inputs': inputs, 'changes': dependency_changes,
                                   'lockBefore': inputs['pubspec.lock'], 'lockAfter': _hash(lock), 'lockDiff': diff,
                                   'resolver': resolver}
            if inputs['pubspec.lock'] != _hash(lock):
                operations.append({'path': 'pubspec.lock', 'before': inputs['pubspec.lock'], 'after': _hash(lock),
                                   'content': base64.b64encode(lock).decode()})
        except Exception as error:
            conflicts.append({'path': 'pubspec.lock', 'reason': 'dependency_resolution_required', 'detail': str(error)})
    unknown = set(resolutions) - used_resolutions
    if unknown:
        raise ValueError('Unused or invalid resolutions: ' + ', '.join(sorted(unknown)))
    for path, content in sorted(baseline_blobs.items()):
        current = _read(root, path)
        if current is not None and current != content:
            raise ValueError(f'Corrupt baseline: {path}')
        if current is None:
            operations.append({'path': path, 'before': None, 'after': _hash(content),
                               'content': base64.b64encode(content).decode()})
    new_metadata['source'] = identity
    new_metadata['upgrade'] = {'sourceSha256': source_before}
    old_metadata = _read(root, 'blueprint.json')
    updated = _json_bytes(new_metadata)
    if old_metadata != updated:
        operations.append({'path': 'blueprint.json', 'before': _hash(old_metadata),
                           'after': _hash(updated), 'content': base64.b64encode(updated).decode()})
    if source_identity(source) != identity:
        raise ValueError('Source changed during planning')
    result = {'schemaVersion': 1, 'root': str(root), 'source': str(source),
              'sourceSha256': source_before, 'sourceIdentity': identity, 'resolutions': resolutions,
              'operations': operations, 'retained': retained, 'conflicts': conflicts,
              'dependencyEvidence': dependency_evidence, 'formatterEvidence': formatter_evidence,
              'applicable': not conflicts}
    result['planSha256'] = _seal(result)
    return result


def _journal(root, transaction):
    if not re.fullmatch(r'[0-9a-f]{32}', transaction):
        raise ValueError('Invalid transaction ID')
    directory = safe_file(root, '.blueprint/upgrades/' + transaction)
    return directory, directory / 'journal.json'


def _write_journal(path, value):
    atomic_write(path, _json_bytes(value))


def apply(root, upgrade_plan):
    """Apply exactly the reviewed plan. Caller must own workspace lock."""
    root = Path(root).resolve()
    if str(root) != upgrade_plan.get('root'):
        raise ValueError('Plan belongs to another workspace')
    unsigned = dict(upgrade_plan)
    signature = unsigned.pop('planSha256', None)
    if signature != _seal(unsigned):
        raise ValueError('Plan integrity check failed')
    # Recompute, including every input and payload, to reject altered/stale plans.
    fresh = plan(root, upgrade_plan['source'], upgrade_plan.get('resolutions'))
    if fresh != upgrade_plan:
        raise ValueError('Plan is stale; generate and review a new plan')
    if not fresh['applicable']:
        raise ValueError('Unresolved upgrade conflicts prevent applying the plan')
    root_transactions = safe_file(root, '.blueprint/upgrades')
    if root_transactions.exists():
        for existing in root_transactions.glob('*/journal.json'):
            state = json.loads(existing.read_text())
            if state.get('state') in ('prepared', 'applying', 'rollback_incomplete'):
                raise ValueError(f'Incomplete transaction: {existing.parent.name}')
    operations = fresh['operations']
    for op in operations:
        if _hash(_read(root, op['path'])) != op['before']:
            raise ValueError(f"Concurrent modification: {op['path']}")
    transaction = uuid.uuid4().hex
    directory, journal_path = _journal(root, transaction)
    directory.mkdir(parents=True, exist_ok=False)
    journal = {'schemaVersion': 1, 'transaction': transaction, 'state': 'prepared', 'files': []}
    for index, op in enumerate(operations):
        before = _read(root, op['path'])
        if _hash(before) != op['before']:
            raise ValueError(f"Concurrent modification during backup: {op['path']}")
        if before is not None:
            atomic_write(directory / str(index), before)
        journal['files'].append({'path': op['path'], 'before': op['before'],
                                 'after': op['after'], 'backup': str(index) if before is not None else None})
    _write_journal(journal_path, journal)
    journal['state'] = 'applying'
    _write_journal(journal_path, journal)
    for op in operations:
        path = safe_file(root, op['path'])
        if _hash(_read(root, op['path'])) != op['before']:
            raise ValueError(f"Concurrent modification; rollback transaction {transaction}: {op['path']}")
        payload = base64.b64decode(op['content'], validate=True)
        if _hash(payload) != op['after']:
            raise ValueError(f"Invalid payload; rollback transaction {transaction}")
        path.parent.mkdir(parents=True, exist_ok=True)
        if 'newFileMode' in op:
            atomic_write(path, payload, new_file_mode=op['newFileMode'])
        else:
            atomic_write(path, payload)
    journal['state'] = 'applied'
    _write_journal(journal_path, journal)
    return {'transaction': transaction, 'state': 'applied', 'files': len(operations)}


def rollback(root, transaction):
    """Restore transaction-owned bytes only; stop on any subsequent user edit."""
    root = Path(root).resolve()
    directory, journal_path = _journal(root, transaction)
    if not journal_path.is_file():
        raise ValueError('Transaction journal missing')
    journal = json.loads(journal_path.read_text())
    if journal.get('transaction') != transaction or journal.get('state') not in ('prepared', 'applying', 'applied', 'rollback_incomplete'):
        raise ValueError('Transaction cannot be rolled back')
    # Preflight all paths before changing any bytes. During an interrupted apply,
    # before means not yet written; after means written by this transaction.
    for item in journal['files']:
        current = _hash(_read(root, item['path']))
        if current not in (item['before'], item['after']):
            raise ValueError(f"Rollback conflict: {item['path']}")
        if item['backup'] is not None and _hash(_read(directory, item['backup'])) != item['before']:
            raise ValueError(f"Backup corrupt: {item['path']}")
    journal['state'] = 'rollback_incomplete'
    _write_journal(journal_path, journal)
    for item in reversed(journal['files']):
        path = safe_file(root, item['path'])
        current = _hash(_read(root, item['path']))
        if current == item['before']:
            continue
        if current != item['after']:
            raise ValueError(f"Rollback conflict: {item['path']}")
        if item['backup'] is None:
            path.unlink()
        else:
            backup = _read(directory, item['backup'])
            if _hash(backup) != item['before']:
                raise ValueError(f"Backup corrupt: {item['path']}")
            atomic_write(path, backup)
    journal['state'] = 'rolled_back'
    _write_journal(journal_path, journal)
    return {'transaction': transaction, 'state': 'rolled_back'}
