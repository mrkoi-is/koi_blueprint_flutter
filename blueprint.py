#!/usr/bin/env python3
"""Pinned, cross-platform blueprint generation and validation (Python stdlib)."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
MIN_PYTHON = (3, 11)
PLATFORMS = ('web', 'android', 'ios', 'macos', 'windows', 'linux')
TEMPLATES = {'minimal': 'starter_app', 'workbench': 'workbench_app'}
REQUIRED_PACKAGES = ('koi_core', 'koi_ui')
IGNORED = shutil.ignore_patterns('.dart_tool', 'build', 'coverage', '.fvm', '__pycache__', '*.g.dart', '*.freezed.dart', '*.pyc', '.flutter-plugins*', '.git', 'Pods', 'ephemeral', '.symlinks', '.swiftpm', '.DS_Store')
RESERVED = set('abstract as assert async augment await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin native new null of on operator part required rethrow return sealed set show static super switch sync this throw true try type typedef var void when while with yield dart flutter test con prn aux nul'.split())
FEATURE_DEPENDENCIES = {
    'presentation': (('flutter',), ('flutter_test',)),
    'api': (('flutter', 'flutter_riverpod', 'riverpod_annotation', 'freezed_annotation', 'json_annotation', 'koi_core'),
            ('flutter_test', 'build_runner', 'riverpod_generator', 'freezed', 'json_serializable')),
    'local': (('flutter', 'flutter_riverpod', 'riverpod_annotation', 'freezed_annotation', 'koi_core'),
              ('flutter_test', 'build_runner', 'riverpod_generator', 'freezed')),
}


class BlueprintError(Exception):
    pass


def run(command, cwd, capture=False):
    print('+ ' + ' '.join(str(item) for item in command), flush=True)
    result = subprocess.run([str(item) for item in command], cwd=cwd, text=True, encoding='utf-8',
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        raise BlueprintError((result.stderr or result.stdout or f'Command failed ({result.returncode})').strip())
    return result.stdout or ''


def pinned_flutter_version(root):
    return json.loads((root / '.fvmrc').read_text(encoding='utf-8'))['flutter']


class SDK:
    def __init__(self, root):
        suffix = '.bat' if os.name == 'nt' else ''
        candidates = [os.environ.get('FLUTTER_BIN'), str(root / '.fvm/flutter_sdk/bin' / ('flutter' + suffix)), shutil.which('flutter')]
        self.flutter = next((Path(p).resolve() for p in candidates if p and Path(p).is_file()), None)
        if self.flutter is None:
            raise BlueprintError('Flutter not found; configure .fvm/flutter_sdk, FLUTTER_BIN, or PATH')
        self.dart = self.flutter.parent / ('dart' + suffix)
        # Code generation can launch dart/flutter itself. Keep those subprocesses
        # on the selected SDK, even when PATH points at a different installation.
        os.environ['PATH'] = str(self.flutter.parent) + os.pathsep + os.environ.get('PATH', '')
        expected = pinned_flutter_version(root)
        actual = json.loads(run([self.flutter, '--version', '--machine'], root, capture=True))['frameworkVersion']
        if actual != expected:
            raise BlueprintError(f'Flutter {expected} required, found {actual}')


def source_root():
    embedded = ROOT / '.blueprint/reference'
    return embedded if embedded.is_dir() else ROOT


def valid_name(value):
    if not re.fullmatch(r'[a-z][a-z0-9]*(?:_[a-z0-9]+)*', value) or value in RESERVED or re.fullmatch(r'(com|lpt)[0-9]', value):
        raise BlueprintError('Name must be a non-reserved snake_case Dart package identifier')
    return value


def platforms(value):
    selected = value.split(',')
    if not selected or len(set(selected)) != len(selected) or any(p not in PLATFORMS for p in selected):
        raise BlueprintError('Platforms must be a unique comma-separated subset of ' + ','.join(PLATFORMS))
    return selected


def pascal(name):
    return ''.join(part.title() for part in name.split('_'))


def camel(name):
    value = pascal(name)
    return value[0].lower() + value[1:]


def copy(source, destination):
    # Never dereference a source symlink into a generated project. Ignored SDK
    # and build trees may contain links; only traversed template inputs matter.
    def checked_ignore(directory, names):
        ignored = IGNORED(directory, names)
        for name in set(names) - set(ignored):
            if (Path(directory) / name).is_symlink():
                raise BlueprintError(f'Symlink in template: {Path(directory) / name}')
        return ignored
    if source.is_symlink():
        raise BlueprintError(f'Symlink template root: {source}')
    shutil.copytree(source, destination, ignore=checked_ignore, dirs_exist_ok=True)


def replace_tree(root, replacements):
    # Paths are renamed deepest first; content substitutions are literal and ordered.
    for path in sorted(root.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.is_file():
            try:
                text = path.read_text(encoding='utf-8')
            except UnicodeError:
                continue
            for old, new in replacements:
                text = text.replace(old, new)
            path.write_text(text, encoding='utf-8')
        name = path.name
        for old, new in replacements:
            name = name.replace(old, new)
        if name != path.name:
            path.rename(path.with_name(name))


def members(root, sdk):
    data = json.loads(run([sdk.dart, 'pub', 'workspace', 'list', '--json'], root, capture=True))
    return [Path(item['path']) for item in data['packages'] if Path(item['path']).resolve() != root.resolve()]


def add_members(manifest, paths):
    text = manifest.read_text(encoding='utf-8')
    manifest.write_text(with_members(text, paths), encoding='utf-8')


def with_members(text, paths):
    match = re.search(r'^workspace:\s*\n((?:[ \t].*\n|\n)*)', text, re.M)
    if not match:
        raise BlueprintError('Expected an explicit workspace list in root pubspec.yaml')
    added = ''.join(f'  - {path}\n' for path in paths if f'  - {path}\n' not in match[0])
    return text[:match.end()] + added + text[match.end():]


def checked_root(value):
    path = Path(value).expanduser().absolute()
    if path.is_symlink():
        raise BlueprintError(f'Refusing a symlink target: {path}')
    return path.resolve()


def safe_target(root, path, must_be_new=False):
    if not path.is_relative_to(root):
        raise BlueprintError(f'Target escapes workspace: {path}')
    current = root
    for part in path.relative_to(root).parts:
        current /= part
        if current.is_symlink():
            raise BlueprintError(f'Refusing a symlink target or parent: {current}')
    if must_be_new and path.exists():
        raise BlueprintError(f'Refusing to overwrite existing path: {path}')


def package_name(spec):
    match = re.search(r'^name:[ \t]*([a-z][a-z0-9_]*)[ \t]*(?:#.*)?$', spec.read_text(encoding='utf-8'), re.M)
    if not match:
        raise BlueprintError(f'Missing or unsupported package name in {spec}')
    return match[1]


def workspace_for(app):
    for candidate in (app, *app.parents):
        spec = candidate / 'pubspec.yaml'
        if spec.is_file() and re.search(r'^workspace:', spec.read_text(encoding='utf-8'), re.M):
            return candidate
    raise BlueprintError('Feature target must belong to a Pub workspace')


def registered_packages(root, sdk):
    result = {}
    for member in members(root, sdk):
        member = member.absolute()
        safe_target(root, member)
        safe_target(root, member / 'pubspec.yaml')
        name = package_name(member / 'pubspec.yaml')
        if name in result:
            raise BlueprintError(f'Duplicate workspace package name: {name}')
        result[name] = member
    return result


def section(text, key):
    """Locate a block mapping without reserializing unrelated user fields."""
    match = re.search(rf'^{re.escape(key)}:[^\n]*(?:\n|$)', text, re.M)
    if not match:
        return None
    if match[0].split(':', 1)[1].strip().split('#', 1)[0].strip():
        raise BlueprintError(f'{key} must use a block mapping')
    end = re.search(r'^\S[^\n]*:', text[match.end():], re.M)
    return match.start(), match.end(), match.end() + end.start() if end else len(text)


def dependency_entries(text, key):
    block = section(text, key)
    if not block:
        return {}
    body = text[block[1]:block[2]]
    items = list(re.finditer(r'^  ([a-z][a-z0-9_]*):[^\n]*(?:\n|$)', body, re.M))
    result = {}
    for index, match in enumerate(items):
        end = items[index + 1].start() if index + 1 < len(items) else len(body)
        # Preserve nested sdk/path/git fields, without consuming section comments.
        content = body[match.start():end].rstrip() + '\n'
        if match[1] in result:
            raise BlueprintError(f'Duplicate dependency {match[1]} in {key}')
        result[match[1]] = content
    meaningful = [line for line in body.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    if any(not line.startswith('  ') or (not line.startswith('    ') and not re.match(r'  [a-z][a-z0-9_]*:', line)) for line in meaningful):
        raise BlueprintError(f'{key} must use two-space dependency entries')
    return result


def with_dependencies(text, template, kind):
    for key, required in zip(('dependencies', 'dev_dependencies'), FEATURE_DEPENDENCIES[kind]):
        existing = dependency_entries(text, key)
        other = dependency_entries(text, 'dev_dependencies' if key == 'dependencies' else 'dependencies')
        available = dependency_entries(template, key)
        additions = []
        for name in required:
            if name in existing or (key == 'dev_dependencies' and name in other):
                continue
            if name in other:
                raise BlueprintError(f'{name} is only in dev_dependencies; move it into dependencies before adding {kind}')
            if name not in available:
                raise BlueprintError(f'Tested feature template is missing dependency {name}')
            additions.append(available[name])
        if additions:
            block = section(text, key)
            if block:
                text = text[:block[2]].rstrip() + '\n' + ''.join(additions) + '\n' + text[block[2]:]
            else:
                text = text.rstrip() + f'\n\n{key}:\n' + ''.join(additions)
    return text


def atomic_bytes(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix='.blueprint-write-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(content)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def commit_changes(root, moves, updates):
    """Install staged trees and manifests together, restoring exact bytes on error."""
    installed, written, created_dirs = [], [], []
    for _, target in moves:
        safe_target(root, target, must_be_new=True)
    for path, original, _ in updates:
        safe_target(root, path)
        if path.read_bytes() != original:
            raise BlueprintError(f'Manifest changed while scaffolding: {path}')
    try:
        for source, target in moves:
            absent = []
            parent = target.parent
            while not parent.exists():
                absent.append(parent)
                parent = parent.parent
            for directory in reversed(absent):
                directory.mkdir()
                created_dirs.append(directory)
            safe_target(root, target, must_be_new=True)
            source.rename(target)
            installed.append(target)
        for path, original, content in updates:
            atomic_bytes(path, content.encode('utf-8'))
            written.append((path, original))
    except Exception:
        for path, original in reversed(written):
            atomic_bytes(path, original)
        for path in reversed(installed):
            shutil.rmtree(path)
        for directory in reversed(created_dirs):
            directory.rmdir()
        raise


def support_package(root, registered, stage, name):
    if name in registered:
        return [], []
    if package_name(root / 'pubspec.yaml') == name:
        raise BlueprintError(f'Workspace root already uses required support package name: {name}')
    target = root / 'packages' / name
    safe_target(root, target, must_be_new=True)
    copy(source_root() / 'packages' / name, stage / name)
    return [(stage / name, target)], [f'packages/{name}']


def rename_feature(root, old, new, package):
    # Paths and imports use snake_case; Dart type/provider identifiers use their
    # proper case. A plain string replacement produces broken api_thingProvider.
    for path in sorted(root.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.is_file():
            text = path.read_text(encoding='utf-8')
            pattern = rf'({pascal(old)})|({old})(?=[A-Z])|({old})'
            text = re.sub(pattern, lambda match: pascal(new) if match[1] else camel(new) if match[2] else new, text)
            text = text.replace('package:feature_lab/', f'package:{package}/')
            path.write_text(text, encoding='utf-8')
        name = path.name.replace(old, new)
        if name != path.name:
            path.rename(path.with_name(name))


def generated_readme(name, template, selected):
    return f'''# {pascal(name)}

Generated {template} Flutter workspace with unified koi_ui themes. Requires Python 3.11+ and the Flutter SDK pinned in `.fvmrc`.

- App: `apps/{name}_app`
- Start with [AI quickstart](docs/ai-quickstart.md).
- Design contract: [DESIGN.md](DESIGN.md).
- Install the pinned SDK with `fvm install` then `fvm use {pinned_flutter_version(ROOT)}`, or set `FLUTTER_BIN` to that SDK executable. The generator does not copy its local SDK.
- Check prerequisites: `python3 blueprint.py doctor --purpose run`.
- List devices: `python3 blueprint.py devices`.
- Launch: `python3 blueprint.py run --app apps/{name}_app --device chrome` (replace chrome with an available device; requires its generated platform).
- Validate: `python3 blueprint.py validate` (Chrome required for browser tests).
- Build: `python3 blueprint.py build --app apps/{name}_app --platforms {",".join(selected)}` (use matching hosts).
- Reference examples live under `.blueprint/reference`; they are not workspace members.
- Tool inventory: [tools](docs/tools.md); compatibility commands: [Melos usage](MELOS_USAGE.md).
- Platform evidence requirements: [platform acceptance](docs/platform-acceptance.md).
'''


def inherit_workspace_assets(stage, name):
    for folder in ('tool', 'scripts', '.agents', '.cursor', 'docs', '.github'):
        if (ROOT / folder).exists():
            copy(ROOT / folder, stage / folder)
    # Historical evidence and exploratory research are source-owned, not
    # instructions or results belonging to the generated project.
    for source_only in ('validation', 'research'):
        inherited = stage / 'docs' / source_only
        if inherited.exists():
            shutil.rmtree(inherited)
    for file in ('blueprint.py', 'AGENTS.md', 'CLAUDE.md', 'README.md', 'DESIGN.md', 'MELOS_USAGE.md', 'CONTRIBUTING.md', 'LICENSE', 'analysis_options.yaml', '.fvmrc', '.gitignore', 'Makefile'):
        if (ROOT / file).exists():
            shutil.copy2(ROOT / file, stage / file)
    agent_entry = stage / 'AGENTS.md'
    if agent_entry.exists():
        agent_text = agent_entry.read_text(encoding='utf-8')
        agent_text = re.sub(r'\A# [^\n]+', f'# {pascal(name)} — Agent 入口', agent_text, count=1)
        agent_entry.write_text(agent_text, encoding='utf-8')
    # References are inert source snapshots, not members or runtime dependencies.
    references = stage / '.blueprint/reference'
    for folder in ('examples', 'packages', 'apps'):
        if (source_root() / folder).exists():
            copy(source_root() / folder, references / folder)
    example_map = stage / 'docs/examples.md'
    if example_map.exists():
        text = example_map.read_text(encoding='utf-8')
        for folder in ('examples', 'apps', 'packages'):
            text = text.replace('../' + folder + '/', '../.blueprint/reference/' + folder + '/')
        example_map.write_text(text, encoding='utf-8')


def create(args):
    name = valid_name(args.name)
    if name in REQUIRED_PACKAGES:
        raise BlueprintError(f'Workspace name {name} conflicts with the required support package')
    from tool.blueprint_config import read_config, choose
    config = read_config(getattr(args, 'config', None))
    template = choose(getattr(args, 'template', None), config, 'template', 'minimal')
    if template not in TEMPLATES:
        raise BlueprintError('Template must be minimal or workbench')
    template_name = TEMPLATES[template]
    template_source = source_root() / 'examples' / template_name
    for required in ('pubspec.yaml', 'lib', 'test'):
        if not (template_source / required).exists():
            raise BlueprintError(f'Missing template input: {template_name}/{required}')
    for package in REQUIRED_PACKAGES:
        if not (source_root() / 'packages' / package / 'pubspec.yaml').is_file():
            raise BlueprintError(f'Missing support package: {package}')
    explicit_platforms = platforms(args.platforms) if args.platforms is not None else None
    selected = choose(explicit_platforms, config, 'platforms', list(PLATFORMS))
    args.org = choose(args.org, config, 'org')
    if not isinstance(args.org, str) or not re.fullmatch(r'[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+', args.org):
        raise BlueprintError('--org must be a lowercase reverse-DNS organization, e.g. com.example')
    output = Path(args.output).expanduser().absolute()
    if output.parent.is_symlink():
        raise BlueprintError('Refusing a symlink output parent')
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise BlueprintError('Refusing to overwrite a nonempty output or symlink')
    output = output.parent.resolve() / output.name
    if output == ROOT or ROOT.is_relative_to(output):
        raise BlueprintError('Output cannot replace the blueprint source or its parent')
    if args.dry_run:
        print(json.dumps({'output': str(output), 'name': name, 'app': f'apps/{name}_app', 'platforms': selected,
                          'template': template, 'packages': list(REQUIRED_PACKAGES), 'configuration': config}, indent=2))
        return
    sdk = SDK(ROOT)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.blueprint-', dir=output.parent))
    was_empty_directory = output.exists()
    installed = False
    try:
        app = stage / 'apps' / f'{name}_app'
        run([sdk.flutter, 'create', '--no-pub', '--empty', '--project-name', f'{name}_app', '--org', args.org,
             '--platforms', ','.join(selected), str(app)], stage)
        for folder in ('lib', 'test'):
            target = app / folder
            if target.exists():
                shutil.rmtree(target)  # Only the newly-created temporary Flutter skeleton.
        # Rename only copied template text, never the already named SDK runners
        # or binary assets. Replace simultaneously for names containing a
        # template identifier themselves.
        inputs = stage / '.app-inputs'
        copy(template_source, inputs)
        replacements = {template_name: f'{name}_app', pascal(template_name): pascal(name) + 'App',
                        'Starter App' if template == 'minimal' else 'Koi Workbench': pascal(name)}
        if config.get('brand', {}).get('displayName'):
            replacements['Starter App' if template == 'minimal' else 'Koi Workbench'] = config['brand']['displayName']
        if template == 'workbench':
            brand_name = config.get('brand', {}).get('displayName')
            replacements['Koi Workspace'] = brand_name or pascal(name)
            replacements['Koi 工作区'] = brand_name or pascal(name) + ' 工作区'
            replacements['Koi 工作區'] = brand_name or pascal(name) + ' 工作區'
        pattern = re.compile('|'.join(re.escape(value) for value in sorted(replacements, key=len, reverse=True)))
        for path in inputs.rglob('*'):
            if path.is_file() and 'assets' not in path.relative_to(inputs).parts and path.suffix in ('.dart', '.yaml', '.md', '.json', '.arb'):
                path.write_text(pattern.sub(lambda match: replacements[match[0]], path.read_text(encoding='utf-8')), encoding='utf-8')
        copy(inputs, app)
        from tool.blueprint_capabilities import registry_content
        (app / 'lib/core/capabilities/installed_capabilities.dart').write_bytes(registry_content(f'{name}_app', [], {}))
        shutil.rmtree(inputs)
        if template == 'workbench':
            from tool.platform_configuration import configure_workbench
            try:
                configure_workbench(app, selected)
            except (OSError, ValueError) as error:
                raise BlueprintError(f'Workbench platform configuration failed: {error}') from error
        for package in REQUIRED_PACKAGES:
            copy(source_root() / 'packages' / package, stage / 'packages' / package)
        inherit_workspace_assets(stage, name)
        (stage / 'README.md').write_text(generated_readme(name, template, selected), encoding='utf-8')
        (stage / 'CHANGELOG.md').write_text(f'# Changelog\n\n## 0.1.0\n\n- Initialize {name} as an independent Flutter workspace.\n', encoding='utf-8')
        options = (stage / 'analysis_options.yaml').read_text(encoding='utf-8')
        if '".blueprint/**"' not in options:
            options = options.replace('  exclude:\n', '  exclude:\n    - ".blueprint/**"\n')
        (stage / 'analysis_options.yaml').write_text(options, encoding='utf-8')
        # Use the existing tested dependency cluster, without example runtime deps.
        root_spec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
        root_spec = re.sub(r'^name:.*$', f'name: {name}', root_spec, count=1, flags=re.M)
        root_spec = re.sub(r'^description:.*$', f'description: {pascal(name)} Flutter workspace', root_spec, count=1, flags=re.M)
        for key in ('repository', 'homepage', 'issue_tracker', 'documentation', 'funding', 'topics', 'screenshots'):
            root_spec = re.sub(rf'^{key}:[^\n]*(?:\n(?:[ \t][^\n]*|)*)?\n?', '', root_spec, flags=re.M)
        root_spec = re.sub(r'^workspace:\s*\n(?:[ \t].*\n|\n)*', f'workspace:\n  - apps/{name}_app\n  - packages/koi_core\n  - packages/koi_ui\n\n', root_spec, count=1, flags=re.M)
        (stage / 'pubspec.yaml').write_text(root_spec, encoding='utf-8')
        # Copy the lockfile as a version seed. Pub prunes unused example deps.
        if (ROOT / 'pubspec.lock').exists():
            shutil.copy2(ROOT / 'pubspec.lock', stage / 'pubspec.lock')
        from tool.blueprint_provenance import initialize_metadata
        initialize_metadata(stage, ROOT, name=name, app=f'apps/{name}_app', platforms=selected, template=template, config=config)
        requested_capabilities = list(config.get('capabilities', []))
        if config.get('brand', {}).get('iconForeground') and 'branding' not in requested_capabilities:
            requested_capabilities.append('branding')
        if requested_capabilities:
            from tool.blueprint_capabilities import install_plan, FileTransaction
            plan = install_plan(stage, app, requested_capabilities, ROOT,
                                config=config.get('capabilityOptions'), brand=config.get('brand'),
                                brand_root=Path(args.config).resolve().parent if args.config else None, fresh=True)
            FileTransaction(stage, plan['changes']).commit()
        display_name = config.get('brand', {}).get('displayName')
        if display_name:
            import hashlib
            from tool.blueprint_display_name import plan_display_name
            from tool.blueprint_capabilities import FileTransaction
            from tool.blueprint_provenance import read_metadata, write_metadata
            display_changes = plan_display_name(app, display_name, selected)
            if display_changes:
                FileTransaction(app, display_changes).commit()
                identity = read_metadata(stage)
                for relative, content in display_changes.items():
                    key = (app.relative_to(stage) / relative).as_posix()
                    identity.setdefault('nativeFiles', {})[key] = hashlib.sha256(content).hexdigest()
                write_metadata(stage, identity)
        if (stage / 'tool/check_ai_assets.py').is_file():
            run([sys.executable, 'tool/check_ai_assets.py', '--root', stage], stage)
        run([sdk.flutter, 'pub', 'get'], stage)
        # The complete app is generated before the destination becomes visible.
        for member in members(stage, sdk):
            if (member / 'l10n.yaml').is_file():
                run([sdk.flutter, 'gen-l10n'], member)
            if 'build_runner:' in (member / 'pubspec.yaml').read_text(encoding='utf-8'):
                run([sdk.dart, 'run', 'build_runner', 'build'], member)
            targets = [member / sub for sub in ('lib', 'test', 'integration_test') if (member / sub).is_dir()]
            if targets:
                run([sdk.dart, 'format', *targets], stage)
        finalize_generated_provenance(stage, app, template_source)
        if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
            raise BlueprintError('Output changed while creating the workspace; nothing was overwritten')
        if output.exists():
            output.rmdir()  # Known-empty destination only.
        stage.rename(output)
        installed = True
        # Pub/Flutter keep absolute workspace and plugin paths. Refresh at the
        # final location before reporting success; never leave the stage path live.
        run([sdk.flutter, 'pub', 'get'], output)
        config = output / '.dart_tool/package_config.json'
        if config.is_file() and (str(stage) in config.read_text(encoding='utf-8') or stage.as_uri() in config.read_text(encoding='utf-8')):
            raise BlueprintError('Pub configuration still references the temporary generation path')
        print(f'Created {output}\nNext: python3 "{output / "blueprint.py"}" validate --workspace "{output}"')
    except Exception:
        if installed:
            shutil.rmtree(output)
        if was_empty_directory and not output.exists():
            output.mkdir()
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def feature(args):
    name = valid_name(args.name)
    app = checked_root(args.path)
    spec = app / 'pubspec.yaml'
    if not spec.is_file():
        raise BlueprintError('Feature target must have a pubspec.yaml')
    root = workspace_for(app)
    safe_target(root, app)
    safe_target(root, spec)
    package = package_name(spec)
    example = {'presentation': 'welcome', 'api': 'catalog', 'local': 'draft'}[args.kind]
    target = app / 'lib/features' / name
    tests = app / 'test/features' / name
    for path in (target, tests):
        safe_target(root, path, must_be_new=True)
    source = source_root() / 'examples/feature_lab'
    original_spec = spec.read_bytes()
    updated_spec = with_dependencies(original_spec.decode('utf-8'), (source / 'pubspec.yaml').read_text(encoding='utf-8'), args.kind)
    if args.dry_run:
        print(f'{args.kind}: {target}\nTests: {tests}\nRequired dependencies: ' + ', '.join(sum(FEATURE_DEPENDENCIES[args.kind], ())))
        return
    sdk = SDK(root)
    registered = registered_packages(root, sdk)
    if registered.get(package) != app:
        raise BlueprintError('Feature target is not a registered Pub workspace member')
    manifest = root / 'pubspec.yaml'
    safe_target(root, manifest)
    original_manifest = manifest.read_bytes()
    stage = Path(tempfile.mkdtemp(prefix='.feature-', dir=root))
    try:
        copy(source / 'lib/features' / example, stage / 'source')
        copy(source / 'test/features' / example, stage / 'tests')
        rename_feature(stage, example, name, package)
        run([sdk.dart, 'format', stage / 'source', stage / 'tests'], root)
        moves = [(stage / 'source', target), (stage / 'tests', tests)]
        additions = []
        if 'koi_core' in FEATURE_DEPENDENCIES[args.kind][0]:
            support_moves, additions = support_package(root, registered, stage, 'koi_core')
            moves.extend(support_moves)
        updates = [(spec, original_spec, updated_spec)]
        if additions:
            updates.append((manifest, original_manifest, with_members(original_manifest.decode('utf-8'), additions)))
        commit_changes(root, moves, updates)
    finally:
        shutil.rmtree(stage)
    print(f'Created {target}\nPublic API: features/{name}/{name}.dart\n'
          f'Integration: add a typed route for {pascal(name)}Page to the target package router.\n'
          'Inject repository ports from bootstrap (see exported providers); never construct them in a page.\n'
          'Then run: python3 blueprint.py check bootstrap; python3 blueprint.py check generate; python3 blueprint.py validate')


def module(args):
    name = valid_name(args.name)
    root = checked_root(args.workspace)
    manifest = root / 'pubspec.yaml'
    if not manifest.is_file():
        raise BlueprintError('Workspace must have pubspec.yaml')
    safe_target(root, manifest)
    destination = root / 'modules' / name
    safe_target(root, destination, must_be_new=True)
    original = manifest.read_bytes()
    # Validate the edit format before copying anything. Pub remains the authority
    # for actual membership; this only preserves and appends the user's list.
    with_members(original.decode('utf-8'), [f'modules/{name}'])
    if args.dry_run:
        print(f'Module: {destination}\nWorkspace registration and koi_modules support will be added')
        return
    sdk = SDK(root)
    registered = registered_packages(root, sdk)
    if name in registered or name == package_name(manifest) or name == 'koi_modules':
        raise BlueprintError(f'Package name already used or reserved for module support: {name}')
    source = source_root() / 'examples/minimal_module'
    if not source.is_dir():
        raise BlueprintError('Tested module source unavailable')
    stage = Path(tempfile.mkdtemp(prefix='.module-', dir=root))
    try:
        copy(source, stage / 'module')
        replace_tree(stage / 'module', [('minimal_module', name), ('MinimalModule', pascal(name)), ('minimalModule', camel(name))])
        run([sdk.dart, 'format', stage / 'module/lib', stage / 'module/test'], root)
        moves, additions = support_package(root, registered, stage, 'koi_modules')
        moves.append((stage / 'module', destination))
        additions.append(f'modules/{name}')
        commit_changes(root, moves, [(manifest, original, with_members(original.decode('utf-8'), additions))])
    finally:
        shutil.rmtree(stage)
    print(f'Created module {name}; registered in pubspec.yaml.\n'
          f'Integration: add {name} to host dependencies; import package:{name}/{name}.dart.\n'
          f'Compose create{pascal(name)}() with KoiModuleCatalog/KoiModuleRuntime and a stable host router; shared infrastructure stays host-owned.\n'
          'Run python3 blueprint.py check bootstrap, generation, and validate before connecting navigation.')


def coverage(root, sdk, workspace, threshold):
    if not 80 <= threshold <= 100:
        raise BlueprintError('Coverage threshold must be between 80 and 100')
    lines = {}
    for member in workspace:
        if not list((member / 'test').rglob('*_test.dart')):
            raise BlueprintError(f'Missing tests: {member}')
        run([sdk.flutter, 'test', '--no-pub', '--coverage'], member)
        report = member / 'coverage/lcov.info'
        if not report.is_file():
            raise BlueprintError(f'Missing coverage report: {report}')
        run([sdk.dart, 'run', 'tool/include_browser_coverage.dart', member.relative_to(root), report], root)
        run([sdk.dart, 'run', 'tool/check_coverage_sources.dart', member.relative_to(root), report], root)
        current = None
        for line in report.read_text(encoding='utf-8').splitlines():
            if line.startswith('SF:'):
                path = Path(line[3:])
                current = (member / path).resolve()
                if not current.is_relative_to(member / 'lib') or 'generated' in current.relative_to(member / 'lib').parts or current.name.endswith(('.g.dart', '.freezed.dart')):
                    current = None
            elif current and line.startswith('DA:'):
                number, hits, *_ = line[3:].split(',')
                key = (current, number)
                lines[key] = lines.get(key, False) or int(hits) > 0
    if not lines:
        raise BlueprintError('No executable handwritten Dart lines in coverage')
    percent = 100 * sum(lines.values()) / len(lines)
    print(f'Handwritten Dart coverage: {percent:.2f}% ({sum(lines.values())}/{len(lines)}), minimum {threshold}%')
    if percent + 0.000001 < threshold:
        raise BlueprintError('Coverage below threshold')


def check(args):
    root = Path(args.workspace).resolve()
    phase = args.phase
    if phase == 'templates':
        run([sys.executable, 'tool/check_template_assets.py', '--root', root], root)
        return
    if phase == 'ai':
        run([sys.executable, 'tool/check_ai_assets.py', '--root', root], root)
        return
    sdk = SDK(root)
    if phase == 'bootstrap':
        run([sdk.flutter, 'pub', 'get'], root)
        return
    workspace = members(root, sdk)
    if phase in ('generate', 'generate-check'):
        for member in workspace:
            if (member / 'l10n.yaml').is_file():
                run([sdk.flutter, 'gen-l10n'], member)
            if 'build_runner:' in (member / 'pubspec.yaml').read_text(encoding='utf-8'):
                run([sdk.dart, 'run', 'build_runner', 'build'], member)
    elif phase in ('format-check', 'format'):
        flags = ['--output=none', '--set-exit-if-changed'] if phase == 'format-check' else []
        targets = [str(path.relative_to(root)) for path in (root / 'tool').rglob('*.dart') if '.dart_tool' not in path.parts]
        targets += [str(member.relative_to(root) / sub) for member in workspace for sub in ('lib', 'test', 'integration_test') if (member / sub).exists()]
        run([sdk.dart, 'format', *flags, *targets], root)
    elif phase == 'analyze':
        run([sdk.dart, 'analyze', '--fatal-infos'], root)
    elif phase == 'test':
        for member in workspace:
            if list((member / 'test').rglob('*_test.dart')):
                run([sdk.flutter, 'test', '--no-pub'], member)
        for path in ('scripts/tests', 'tool/tests'):
            if (root / path).exists():
                run([sys.executable, '-m', 'unittest', 'discover', '-s', path, '-p', 'test_*.py'], root)
        for test_file in sorted((root / 'tool/tests').glob('*_test.dart')):
            run([sdk.dart, 'run', test_file], root)
    elif phase == 'browser':
        for member in workspace:
            tests = member / 'test/browser'
            if list(tests.glob('*_test.dart')):
                run([sdk.flutter, 'test', '--no-pub', '--platform', 'chrome', 'test/browser'], member)
    elif phase == 'architecture':
        run([sdk.dart, 'run', 'tool/check_architecture.dart', '--root', root], root)
    elif phase == 'coverage':
        coverage(root, sdk, workspace, args.coverage_min)


def validate(args):
    root = Path(args.workspace).resolve()
    sdk = SDK(root)
    validation_prerequisites(root, members(root, sdk))
    run([sdk.flutter, 'pub', 'get', '--enforce-lockfile'], root)
    if not (root / 'blueprint.json').exists():
        check(argparse.Namespace(workspace=str(root), phase='templates'))
    for phase in ('generate-check', 'format-check', 'architecture', 'ai', 'analyze', 'test', 'browser', 'coverage'):
        check(argparse.Namespace(workspace=str(root), phase=phase, coverage_min=args.coverage_min))
    smoke = root / 'packages/koi_api_bootstrap/test/web_compile_smoke.dart'
    if smoke.exists():
        with tempfile.TemporaryDirectory(prefix='blueprint-web-') as temporary:
            output = Path(temporary) / 'smoke.js'
            run([sdk.dart, 'compile', 'js', smoke, '-o', output], root)
            run(['node', output], root)
    print('Validation passed; platform builds are separate and must run on their matching hosts.')


def build(args):
    from tool.blueprint_config import DEFAULT_ARCH
    from tool.blueprint_provenance import read_metadata
    from tool.blueprint_build import build_target, manifest_path
    app = checked_root(args.app)
    root = workspace_for(app)
    sdk = SDK(root)
    if app not in members(root, sdk):
        raise BlueprintError('Build target must be an active workspace member')
    def announce(name, result):
        print(json.dumps({
            'status': result['status'],
            'manifest': str(manifest_path(app, name)),
            'buildInfo': {
                'version': result['version'], 'build': result['build'],
                'source': result['source']['sourceSha256'],
                'channel': result['profile']['channel'],
                'platform': result['profile']['platform'],
                'architecture': result['profile']['arch'],
            },
        }, ensure_ascii=False))
    profile_name = getattr(args, 'profile', None)
    if profile_name:
        if getattr(args, 'platforms', None):
            raise BlueprintError('Use either --profile or --platforms')
        metadata = read_metadata(root) or {}
        profiles = metadata.get('configuration', {}).get('buildProfiles', {})
        if profile_name not in profiles:
            raise BlueprintError(f'Unknown build profile: {profile_name}')
        announce(profile_name, build_target(app, root, sdk, profile_name,
                                            profiles[profile_name], run))
    else:
        if not getattr(args, 'platforms', None):
            raise BlueprintError('build requires --platforms or --profile')
        for target in platforms(args.platforms):
            profile_name = target + '-release'
            announce(profile_name, build_target(app, root, sdk, profile_name,
                                                {'platform': target, 'arch': DEFAULT_ARCH[target]}, run))


def package(args):
    from tool.blueprint_build import package_target
    app = checked_root(args.app)
    root = workspace_for(app)
    print(package_target(app, root, args.profile, run))


def upgrade_report(args):
    from tool.blueprint_provenance import upgrade_report as report
    app = checked_root(args.app)
    print(json.dumps(report(workspace_for(app), checked_root(args.source)), ensure_ascii=False, indent=2))


def capability(args):
    from tool.blueprint_capabilities import catalog, install_plan, FileTransaction, snapshot_install_inputs
    from tool.blueprint_provenance import read_metadata
    app = checked_root(args.app)
    root = workspace_for(app)
    entries = catalog(ROOT)
    metadata = read_metadata(root) or {}
    if args.action == 'list':
        print(json.dumps([{**item, 'installed': key in metadata.get('capabilities', {})}
                          for key, item in entries.items()], ensure_ascii=False, indent=2))
        return
    config = {}
    configured = {}
    if args.config:
        from tool.blueprint_config import read_config
        configured = read_config(args.config)
        if configured.get('capabilities') and args.id not in configured['capabilities']:
            raise BlueprintError('Selected capability conflicts with configuration')
    config = configured.get('capabilityOptions', {})
    snapshot = snapshot_install_inputs(root, app)
    plan = install_plan(root, app, [args.id], ROOT, config=config, brand=configured.get('brand'),
                        brand_root=Path(args.config).resolve().parent if args.config else None)
    print(json.dumps({key: value for key, value in plan.items() if key != 'changes'}, indent=2))
    if args.dry_run or not plan['changes']:
        return
    # Resolve all recipe dependencies in one isolated staging workspace, then
    # publish source/manifests/lock together. Refresh only derived local paths.
    transaction = FileTransaction(root, {**plan['changes'], 'pubspec.lock': (root / 'pubspec.lock').read_bytes()},
                                  expected_hashes=snapshot)
    sdk = SDK(root)
    with tempfile.TemporaryDirectory(prefix='.capability-', dir=root.parent) as temporary:
        stage = Path(temporary)
        def ignored(directory, names):
            excluded = {'.git', 'Pods', 'ephemeral', '.symlinks'}
            # The workspace reference/baseline tree is large and is not needed
            # for Pub. App-local receipts belong to installed asset generators
            # and must survive the staged install unchanged.
            if Path(directory).resolve() == root:
                excluded.add('.blueprint')
            return set(IGNORED(directory, names)) | (set(names) & excluded)
        shutil.copytree(root, stage, dirs_exist_ok=True, ignore=ignored, symlinks=True)
        for relative, content in plan['changes'].items():
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        staged_app = stage / app.relative_to(root)
        run([sdk.flutter, 'pub', 'get'], stage)
        for member in members(stage, sdk):
            if (member / 'l10n.yaml').is_file():
                run([sdk.flutter, 'gen-l10n'], member)
            if 'build_runner:' in (member / 'pubspec.yaml').read_text(encoding='utf-8'):
                run([sdk.dart, 'run', 'build_runner', 'build'], member)
        dart_targets = [stage / relative for relative in plan['changes'] if relative.endswith('.dart')]
        if dart_targets:
            run([sdk.dart, 'format', *dart_targets], stage)
        receipt = read_metadata(stage)
        import hashlib
        registration = app.relative_to(root) / 'lib/core/capabilities/installed_capabilities.dart'
        receipt['registrySha256'] = hashlib.sha256((stage / registration).read_bytes()).hexdigest()
        for item in receipt['capabilities'].values():
            for relative in item['files']:
                item['files'][relative] = hashlib.sha256((stage / relative).read_bytes()).hexdigest()
        from tool.blueprint_provenance import plan_install_baseline, write_metadata
        changes = {relative: (stage / relative).read_bytes() for relative in plan['changes']
                   if relative != 'blueprint.json'}
        baseline_blobs = plan_install_baseline(root, ROOT, metadata, receipt, changes)
        write_metadata(stage, receipt)
        changes['blueprint.json'] = (stage / 'blueprint.json').read_bytes()
        changes.update(baseline_blobs)
        changes['pubspec.lock'] = (stage / 'pubspec.lock').read_bytes()
        transaction.changes = changes
        from tool.blueprint_capabilities import safe_file
        for relative in baseline_blobs:
            path = safe_file(root, relative)
            transaction.before[relative] = path.read_bytes() if path.is_file() else None
        def refresh():
            run([sdk.flutter, 'pub', 'get', '--enforce-lockfile'], root)
            if (app / 'l10n.yaml').is_file():
                run([sdk.flutter, 'gen-l10n'], app)
            run([sdk.dart, 'run', 'build_runner', 'build'], app)
        transaction.commit(refresh)


def finalize_generated_provenance(stage, app, template_source):
    import hashlib
    from tool.blueprint_provenance import record_baseline, read_metadata, write_metadata
    origins = {}
    for path in template_source.rglob('*'):
        if path.is_file() and not path.is_symlink() and not any(p in ('.dart_tool', 'build', 'coverage', 'generated') for p in path.parts) and not path.name.endswith(('.g.dart', '.freezed.dart')):
            relative = path.relative_to(template_source)
            if (app / relative).is_file():
                origins[(app / relative).relative_to(stage).as_posix()] = f'examples/{template_source.name}/{relative.as_posix()}'
    for folder in ('packages', 'tool', 'scripts', '.agents'):
        base = stage / folder
        for path in base.rglob('*'):
            if path.is_file() and not path.is_symlink() and not any(p in ('.dart_tool', 'build', 'coverage', '__pycache__', 'generated') for p in path.relative_to(base).parts) and not path.name.endswith(('.g.dart', '.freezed.dart', '.pyc')):
                origins[path.relative_to(stage).as_posix()] = path.relative_to(stage).as_posix()
    origins['blueprint.py'] = 'blueprint.py'
    origins['pubspec.yaml'] = 'pubspec.yaml'
    for installed in read_metadata(stage)['capabilities'].values():
        origins.update(installed.get('origins', {}))
        for relative in installed.get('files', {}):
            origins.setdefault(relative, None)
    for relative in read_metadata(stage).get('nativeFiles', {}):
        origins.setdefault(relative, None)
    record_baseline(stage, origins)
    metadata = read_metadata(stage)
    for relative, entry in metadata['managedFiles'].items():
        if entry['source'] is None:
            continue
        path = source_root() / entry['source']
        if not path.is_file():
            path = ROOT / entry['source']
        if path.is_file():
            entry['sourceSha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    registration = app / 'lib/core/capabilities/installed_capabilities.dart'
    if registration.is_file():
        metadata['registrySha256'] = hashlib.sha256(registration.read_bytes()).hexdigest()
    for receipt in metadata['capabilities'].values():
        for relative in receipt['files']:
            receipt['files'][relative] = hashlib.sha256((stage / relative).read_bytes()).hexdigest()
    write_metadata(stage, metadata)


def launch(args):
    app = Path(args.app).resolve()
    root = workspace_for(app)
    sdk = SDK(root)
    if app not in members(root, sdk) or not (app / 'lib/main.dart').is_file():
        raise BlueprintError('Run app must be an active workspace member with lib/main.dart')
    run([sdk.flutter, 'run', '-d', args.device], app)


def devices(args):
    root = Path(args.workspace).resolve()
    sdk = SDK(root)
    run([sdk.flutter, 'devices'], root)


def validation_prerequisites(root, workspace):
    missing = []
    # Chrome may be explicitly configured for CI.
    configured_chrome = os.environ.get('CHROME_EXECUTABLE')
    chrome = configured_chrome if configured_chrome else next((p for p in (
        shutil.which('google-chrome'), shutil.which('chromium'), shutil.which('chrome'),
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        os.path.expandvars(r'%PROGRAMFILES%/Google/Chrome/Application/chrome.exe'),
        os.path.expandvars(r'%LOCALAPPDATA%/Google/Chrome/Application/chrome.exe'),
    ) if p and Path(p).is_file()), None)
    needs_chrome = any(list((member / 'test/browser').glob('*_test.dart')) for member in workspace)
    if needs_chrome and (not chrome or not Path(chrome).is_file()):
        missing.append('Chrome for active browser tests (or set CHROME_EXECUTABLE to an existing executable)')
    if (root / 'packages/koi_api_bootstrap/test/web_compile_smoke.dart').exists() and not shutil.which('node'):
        missing.append('Node for the source API Web smoke')
    if missing:
        raise BlueprintError('Missing validation tools: ' + ', '.join(missing))


def doctor(args):
    root = Path(args.workspace).resolve()
    sdk = SDK(root)
    print(f'Python {sys.version_info.major}.{sys.version_info.minor}; selected Flutter: {sdk.flutter}')
    if args.purpose == 'validate':
        validation_prerequisites(root, members(root, sdk))
    from tool.blueprint_provenance import read_metadata
    from tool.blueprint_environment import capability_doctor, doctor_report
    metadata = read_metadata(root) or {}
    config = metadata.get('configuration', {})
    formats = [profile['format'] for profile in config.get('buildProfiles', {}).values() if 'format' in profile]
    report = doctor_report(formats=formats, profiles=config.get('buildProfiles', {}).values(),
                           branding='branding' in metadata.get('capabilities', {}))
    report['installedCapabilities'] = sorted(metadata.get('capabilities', {}))
    app_relative = Path(metadata.get('app', ''))
    if report['installedCapabilities'] and not app_relative.is_absolute() and '..' not in app_relative.parts:
        app = root / app_relative
        if app.is_dir():
            report['capabilityDiagnostics'] = capability_doctor(app, metadata['capabilities'])
            if report['capabilityDiagnostics']['status'] == 'FAIL':
                report['status'] = 'FAIL'
            elif report['capabilityDiagnostics']['status'] == 'INCOMPLETE' and report['status'] == 'PASS':
                report['status'] = 'INCOMPLETE'
    print(json.dumps(report, ensure_ascii=False, indent=2))
    run([sdk.flutter, 'doctor', '-v'], root)
    print('Blueprint prerequisites checked; target devices and platform toolchains must also be available.')


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        print('blueprint: Python 3.11 or newer is required; no files were changed', file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create_parser = commands.add_parser('create', help='Create an independent Flutter workspace', description='Create minimal or workbench from tested sources. Uses a temporary directory and rolls back on failure.')
    create_parser.add_argument('name', help='Non-reserved snake_case workspace name')
    create_parser.add_argument('--output', required=True, help='New output directory; existing nonempty targets are rejected')
    create_parser.add_argument('--org', help='Reverse-domain application organization, e.g. com.example')
    create_parser.add_argument('--platforms', default=None, help='Comma-separated subset: ' + ','.join(PLATFORMS) + ' (default: all)')
    create_parser.add_argument('--template', choices=tuple(TEMPLATES), default=None, help='minimal: simple App; workbench: documents, media and tasks (default: minimal)')
    create_parser.add_argument('--dry-run', action='store_true', help='Show the plan without writing files or resolving dependencies')
    create_parser.add_argument('--config', help='Versioned JSON configuration for capabilities, locales, branding and builds')
    feature_parser = commands.add_parser('feature', help='Add a tested Feature to an active App or module', description='Generate presentation (UI only), api (repository/provider), or local (persistent draft) Feature. Wire navigation and real business fields afterwards.')
    feature_parser.add_argument('path', help='Path to the active App/module package')
    feature_parser.add_argument('name', help='New snake_case Feature name')
    feature_parser.add_argument('--kind', choices=['presentation', 'api', 'local'], required=True, help='Required source template and dependency set')
    feature_parser.add_argument('--dry-run', action='store_true', help='Show the plan without writing files or resolving dependencies')
    module_parser = commands.add_parser('module', help='Add an independent business module', description='Generate a koi_modules business boundary; host registration and services remain explicit.')
    module_parser.add_argument('name', help='New snake_case module name')
    module_parser.add_argument('--workspace', required=True, help='Destination workspace root')
    module_parser.add_argument('--dry-run', action='store_true', help='Show the plan without writing files or resolving dependencies')
    validate_parser = commands.add_parser('validate', help='Run the complete local quality gate', description='Strict lockfile, source-only templates, generation, format, architecture, AI assets, analysis, tests, active Chrome tests and 80% coverage. Source API Web smoke also requires Node. Platform builds are separate.')
    check_parser = commands.add_parser('check', help='Run one quality phase', description='bootstrap resolves dependencies; generate and generate-check both rebuild untracked Dart parts (reproducibility, not a read-only drift check). format rewrites; format-check is read-only. browser runs active test/browser tests. templates checks source template assets. Other phases: architecture, ai, analyze, test, coverage.')
    check_parser.add_argument('phase', choices=['bootstrap', 'generate', 'generate-check', 'format', 'format-check', 'analyze', 'test', 'browser', 'coverage', 'architecture', 'ai', 'templates'], help='Quality phase to run; see descriptions above')
    for item in (validate_parser, check_parser):
        item.add_argument('--workspace', default=str(ROOT), help='Workspace root (default: directory containing blueprint.py)')
        item.add_argument('--coverage-min', type=float, default=80, help='Minimum handwritten line coverage percentage (default: 80)')
    build_parser = commands.add_parser('build', help='Build profiled artifacts on compatible hosts', description='Build selected platforms with a named profile or local defaults and write a verified artifact manifest. iOS signing follows the profile; a successful build does not prove device runtime.')
    build_parser.add_argument('--app', required=True, help='App package path with selected platform runners')
    build_parser.add_argument('--platforms', help='Unique comma-separated platform subset; builds need matching hosts')
    build_parser.add_argument('--profile', help='Named build profile from blueprint.json')
    package_parser = commands.add_parser('package', help='Package a verified matching build; never publish')
    package_parser.add_argument('--app', required=True)
    package_parser.add_argument('--profile', required=True)
    report_parser = commands.add_parser('upgrade-report', help='Read-only three-way upgrade report; no project writes')
    report_parser.add_argument('--app', required=True)
    report_parser.add_argument('--source', required=True)
    capability_parser = commands.add_parser('capability', help='Inspect or install tested optional capability recipes')
    capability_actions = capability_parser.add_subparsers(dest='action', required=True)
    capability_list = capability_actions.add_parser('list')
    capability_add = capability_actions.add_parser('add')
    for item in (capability_list, capability_add):
        item.add_argument('--app', required=True)
    capability_add.add_argument('id')
    capability_add.add_argument('--config')
    capability_add.add_argument('--dry-run', action='store_true')
    run_parser = commands.add_parser('run', help='Launch an active App on a selected device', description='Run an active workspace App with the pinned SDK. Use devices first; the App must have that platform runner.')
    run_parser.add_argument('--app', required=True, help='Active App package path, e.g. apps/demo_app')
    run_parser.add_argument('--device', required=True, help='Device ID from devices, e.g. chrome or macos')
    devices_parser = commands.add_parser('devices', help='List devices using the workspace SDK')
    doctor_parser = commands.add_parser('doctor', help='Check SDK and purpose-specific prerequisites', description='Run Flutter doctor. With --purpose validate, check Chrome only when active members contain browser tests, and Node only for the API Web smoke.')
    for item in (devices_parser, doctor_parser):
        item.add_argument('--workspace', default=str(ROOT), help='Workspace root (default: directory containing blueprint.py)')
    doctor_parser.add_argument('--purpose', choices=('run', 'validate'), default='run', help='run: SDK/platform doctor; validate: additionally inspect active test prerequisites')
    args = parser.parse_args(argv)
    try:
        (launch if args.command == 'run' else globals()[args.command.replace('-', '_')])(args)
        return 0
    except (BlueprintError, OSError, ValueError) as error:
        print(f'blueprint: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
