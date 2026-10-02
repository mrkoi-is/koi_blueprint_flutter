"""Content-based provenance and read-only three-way blueprint comparisons."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import shutil

from tool.blueprint_config import digest
from tool.platform_evidence import source_manifest


def source_identity(root):
    root = Path(root)
    source = source_manifest(root)
    if not shutil.which('git'):
        return {'commit': None, 'dirty': None, 'sourceSha256': source['source_sha256'], 'generatorVersion': 2}
    status = subprocess.run(['git', 'status', '--porcelain'], cwd=root, capture_output=True, text=True)
    # A directory nested inside an unrelated Git repository is not its source.
    top = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=root, capture_output=True, text=True)
    owned_git = top.returncode == 0 and Path(top.stdout.strip()).resolve() == root.resolve()
    return {'commit': source['baseline_commit'] if owned_git else None,
            'dirty': bool(status.stdout.strip()) if owned_git else None,
            'sourceSha256': source['source_sha256'], 'generatorVersion': 2}


def read_metadata(root):
    file = Path(root) / 'blueprint.json'
    if not file.exists():
        return None
    value = json.loads(file.read_text(encoding='utf-8'))
    if not isinstance(value, dict) or value.get('schema') not in (1, 2):
        raise ValueError('Unknown blueprint.json schema; refusing to modify the project')
    return value


def initialize_metadata(root, source, *, name, app, platforms, template, config):
    parent = read_metadata(source)
    identity = source_identity(source)
    value = {'schema': 2, 'name': name, 'app': app, 'platforms': platforms, 'template': template,
             'source': identity, 'parent': parent.get('source') if parent else None,
             'origin': parent.get('origin', parent.get('source')) if parent else identity,
             'configuration': config, 'configurationSha256': digest(config),
             'capabilities': {}, 'managedFiles': {}}
    write_metadata(root, value)
    return value


def write_metadata(root, value):
    (Path(root) / 'blueprint.json').write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def record_baseline(root, origins):
    """Record only copied source inputs, excluding SDK outputs and local data."""
    root = Path(root)
    value = read_metadata(root)
    baseline = root / '.blueprint/baseline'
    for relative, origin in sorted(origins.items()):
        path = root / relative
        if not path.is_file() or path.is_symlink():
            continue
        content = path.read_bytes()
        sha = hashlib.sha256(content).hexdigest()
        stored = baseline / sha
        stored.parent.mkdir(parents=True, exist_ok=True)
        if not stored.exists():
            stored.write_bytes(content)
        value['managedFiles'][relative] = {'sha256': sha, 'source': origin}
    write_metadata(root, value)


def plan_install_baseline(root, source, previous, receipt, changes):
    """Plan capability baselines without accepting pre-existing user edits.

    The caller publishes the returned blobs and blueprint.json in the same
    compare-before-write transaction as the capability files.
    """
    root, source = Path(root).resolve(), Path(source).resolve()
    owned = set(previous.get('managedFiles', {})) | set(receipt.get('nativeFiles', {}))
    if 'pubspec.yaml' in changes:
        owned.add('pubspec.yaml')
    origins = {}
    for capability in receipt.get('capabilities', {}).values():
        owned.update(capability.get('files', {}))
        origins.update(capability.get('origins', {}))
    receipt.setdefault('managedFiles', {})
    blobs = {}
    for relative, content in changes.items():
        if relative not in owned or relative in ('blueprint.json', 'pubspec.lock'):
            continue
        candidate = Path(relative)
        if candidate.is_absolute() or '..' in candidate.parts:
            raise ValueError('Invalid managed file path')
        original = previous.get('managedFiles', {}).get(relative)
        current = root / candidate
        if original and (not current.is_file() or hashlib.sha256(current.read_bytes()).hexdigest() != original['sha256']):
            # A legitimate local edit may be preserved by the installer, but it
            # must remain visible as local work in a later upgrade report.
            continue
        sha = hashlib.sha256(content).hexdigest()
        origin = original.get('source') if original else origins.get(relative)
        if relative == 'pubspec.yaml' and origin is None:
            origin = 'pubspec.yaml'
        entry = {'sha256': sha, 'source': origin}
        if origin is not None:
            upstream = Path(origin)
            if upstream.is_absolute() or '..' in upstream.parts:
                raise ValueError('Invalid managed source path')
            upstream_file = source / upstream
            if not upstream_file.is_file():
                upstream_file = source / '.blueprint/reference' / upstream
            if upstream_file.is_file() and not upstream_file.is_symlink():
                entry['sourceSha256'] = hashlib.sha256(upstream_file.read_bytes()).hexdigest()
            elif original and 'sourceSha256' in original:
                entry['sourceSha256'] = original['sourceSha256']
        receipt['managedFiles'][relative] = entry
        blob = f'.blueprint/baseline/{sha}'
        existing = root / blob
        if existing.is_file():
            if existing.read_bytes() != content:
                raise ValueError(f'Corrupt baseline content: {blob}')
        else:
            blobs[blob] = content
    return blobs


def upgrade_report(root, source):
    root, source = Path(root).resolve(), Path(source).resolve()
    value = read_metadata(root)
    report = {'schema': 1, 'project': str(root), 'source': str(source), 'writesProject': False,
              'upstreamChanges': [], 'localChanges': [], 'conflicts': [], 'alreadyApplied': [], 'unchanged': [],
              'manualMigration': [], 'newCapabilities': [], 'capabilityUpdates': []}
    if not value or value['schema'] == 1:
        report['manualMigration'].extend([
            'Schema 1 or missing baseline: a reliable three-way comparison is unavailable; no files were changed.',
            'Keep the existing project intact and generate a separate schema 2 project from the target blueprint with the same template and platforms.',
            'Compare the existing App, native runners, pubspec and lockfile against the separate project; port business changes and capability hooks manually.',
            'Run validate and platform checks in the migrated copy, then establish managed baselines only for files whose origin and contents were verified.',
        ])
        return report
    for relative, entry in value.get('managedFiles', {}).items():
        candidate = Path(relative)
        origin_value = entry.get('source')
        origin = Path(origin_value) if origin_value is not None else None
        if candidate.is_absolute() or '..' in candidate.parts or (origin is not None and (origin.is_absolute() or '..' in origin.parts)):
            raise ValueError('Invalid managed file path')
        local = root / candidate
        upstream = source / origin if origin is not None else None
        # An independent generated workspace keeps source examples in its
        # read-only reference tree. Recursive generation uses that tree as the
        # next source, so both origins are valid without rewriting a baseline.
        if upstream is not None and not upstream.is_file():
            upstream = source / '.blueprint/reference' / origin
        if local.is_symlink() or (upstream is not None and upstream.is_symlink()) or not local.resolve().is_relative_to(root) or (upstream is not None and not upstream.resolve().is_relative_to(source)):
            raise ValueError('Managed path must not escape through symlinks')
        current = hashlib.sha256(local.read_bytes()).hexdigest() if local.is_file() else None
        upstream_content = upstream.read_bytes() if upstream is not None and upstream.is_file() else None
        new = hashlib.sha256(upstream_content).hexdigest() if upstream_content is not None else None
        old = entry['sha256']
        # Source baseline is distinct from the renamed generated-project bytes.
        source_old = entry.get('sourceSha256', old)
        local_changed, upstream_changed = current != old, origin is not None and new != source_old
        rendered = upstream_content
        if rendered is not None and origin is not None and candidate.suffix == '.dart' and value.get('app'):
            package = Path(value['app']).name
            rendered = rendered.replace(b'__APP_PACKAGE__', package.encode('utf-8'))
            # The creator and capability installer rewrite imports from source
            # examples to the generated App package. Compare the rendered bytes,
            # otherwise an already adopted upstream fix looks like a conflict.
            if len(origin.parts) > 2 and origin.parts[0] == 'examples':
                old_package = origin.parts[1]
                rendered = rendered.replace(
                    f'package:{old_package}/'.encode('utf-8'),
                    f'package:{package}/'.encode('utf-8'),
                )
        same_new_content = (rendered is not None and current == hashlib.sha256(rendered).hexdigest())
        category = ('alreadyApplied' if local_changed and upstream_changed and same_new_content else
                    'conflicts' if local_changed and upstream_changed else
                    'upstreamChanges' if upstream_changed else 'localChanges' if local_changed else 'unchanged')
        report[category].append({'path': relative, 'source': entry['source'], 'baseline': old, 'current': current, 'upstream': new})
    catalog = source / 'tool/capabilities/catalog.json'
    if catalog.is_file():
        entries = {item['id']: item for item in json.loads(catalog.read_text())['capabilities']}
        report['newCapabilities'] = [key for key, item in entries.items()
                                     if key not in value.get('capabilities', {}) and
                                     (item.get('recipe') or item.get('extraSources') or item.get('tool'))]
        for key, installed in value.get('capabilities', {}).items():
            item = entries.get(key)
            if item is None:
                report['manualMigration'].append(f'Installed capability {key} is absent from the target catalog.')
                continue
            reasons = []
            if item['version'] != installed.get('version'):
                reasons.append(f'version {installed.get("version")} → {item["version"]}')
            for locale, origin_name in item.get('localizationSources', {}).items():
                prior = installed.get('localizations', {}).get(locale)
                if prior is None or prior.get('source') != origin_name:
                    reasons.append(f'{locale} localization source added or changed')
            for locale, prior in installed.get('localizations', {}).items():
                origin = Path(prior['source'])
                if origin.is_absolute() or '..' in origin.parts:
                    raise ValueError('Invalid capability localization path')
                target = source / origin
                if not target.is_file():
                    target = source / '.blueprint/reference' / origin
                current = hashlib.sha256(target.read_bytes()).hexdigest() if target.is_file() else None
                if current != prior['sourceSha256']:
                    reasons.append(f'{locale} localization changed')
            if reasons:
                report['capabilityUpdates'].append({'id': key, 'reasons': reasons})
    return report
