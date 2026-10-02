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
IGNORED = shutil.ignore_patterns('.dart_tool', 'build', 'coverage', '.fvm', '__pycache__', '*.g.dart', '*.freezed.dart', '*.pyc', '.flutter-plugins*')
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
        expected = json.loads((root / '.fvmrc').read_text(encoding='utf-8'))['flutter']
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


def create(args):
    name = valid_name(args.name)
    if name in REQUIRED_PACKAGES:
        raise BlueprintError(f'Workspace name {name} conflicts with the required support package')
    template = getattr(args, 'template', 'minimal')
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
    selected = platforms(args.platforms)
    if not re.fullmatch(r'[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+', args.org):
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
                          'template': template, 'packages': list(REQUIRED_PACKAGES)}, indent=2))
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
        if template == 'workbench':
            replacements['Koi 工作区'] = pascal(name) + ' 工作区'
        pattern = re.compile('|'.join(re.escape(value) for value in sorted(replacements, key=len, reverse=True)))
        for path in inputs.rglob('*'):
            if path.is_file() and 'assets' not in path.relative_to(inputs).parts and path.suffix in ('.dart', '.yaml', '.md', '.json'):
                path.write_text(pattern.sub(lambda match: replacements[match[0]], path.read_text(encoding='utf-8')), encoding='utf-8')
        copy(inputs, app)
        shutil.rmtree(inputs)
        if template == 'workbench':
            from tool.platform_configuration import configure_workbench
            try:
                configure_workbench(app, selected)
            except (OSError, ValueError) as error:
                raise BlueprintError(f'Workbench platform configuration failed: {error}') from error
        for package in REQUIRED_PACKAGES:
            copy(source_root() / 'packages' / package, stage / 'packages' / package)
        for folder in ('tool', 'scripts', '.agents', '.cursor', 'docs', '.github'):
            if (ROOT / folder).exists():
                copy(ROOT / folder, stage / folder)
        # Historical evidence and exploratory research are source-owned, not
        # instructions or results belonging to the generated project.
        for source_only in ('validation', 'research'):
            inherited = stage / 'docs' / source_only
            if inherited.exists():
                shutil.rmtree(inherited)
        for file in ('blueprint.py', 'AGENTS.md', 'CLAUDE.md', 'README.md', 'DESIGN.md', 'CONTRIBUTING.md', 'LICENSE', 'analysis_options.yaml', '.fvmrc', '.gitignore', 'Makefile'):
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
        design_entry = '- Design contract: [DESIGN.md](DESIGN.md).\n' if (stage / 'DESIGN.md').is_file() else ''
        (stage / 'README.md').write_text(f'# {pascal(name)}\n\nGenerated {template} Flutter workspace with unified koi_ui themes. Requires Python 3.11+ and the Flutter SDK pinned in `.fvmrc`.\n\n- App: `apps/{name}_app`\n- Start with [AI quickstart](docs/ai-quickstart.md).\n{design_entry}- Run `python3 blueprint.py validate`.\n- Build: `python3 blueprint.py build --app apps/{name}_app --platforms {",".join(selected)}` (use matching hosts).\n- Reference examples live under `.blueprint/reference`; they are not workspace members.\n', encoding='utf-8')
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
        (stage / 'blueprint.json').write_text(json.dumps({'schema': 1, 'name': name, 'app': f'apps/{name}_app', 'platforms': selected, 'template': template}, indent=2) + '\n', encoding='utf-8')
        run([sdk.flutter, 'pub', 'get'], stage)
        # The complete app is generated before the destination becomes visible.
        for member in members(stage, sdk):
            if 'build_runner:' in (member / 'pubspec.yaml').read_text(encoding='utf-8'):
                run([sdk.dart, 'run', 'build_runner', 'build'], member)
            targets = [member / sub for sub in ('lib', 'test', 'integration_test') if (member / sub).is_dir()]
            if targets:
                run([sdk.dart, 'format', *targets], stage)
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
                if not current.is_relative_to(member / 'lib') or current.name.endswith(('.g.dart', '.freezed.dart')):
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
    run([sdk.flutter, 'pub', 'get', '--enforce-lockfile'], root)
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
    selected = platforms(args.platforms)
    app = Path(args.app).resolve()
    if not (app / 'pubspec.yaml').is_file():
        raise BlueprintError('Build app must have pubspec.yaml')
    sdk = SDK(ROOT)
    host_targets = {'darwin': {'ios', 'macos'}, 'win32': {'windows'}, 'linux': {'linux'}}.get(sys.platform, set()) | {'web', 'android'}
    for target in selected:
        if target not in host_targets:
            raise BlueprintError(f'{target} cannot be built on {sys.platform}; use corresponding CI host')
        if not (app / target).is_dir():
            raise BlueprintError(f'{target} platform directory is missing in {app}')
    for target in selected:
        command = [sdk.flutter, 'build', 'apk' if target == 'android' else target, '--release', '--no-pub']
        if target == 'ios':
            command += ['--no-codesign']
        # The legacy auth demo intentionally requires an explicit environment.
        if re.search(r'^name: koi_admin_app$', (app / 'pubspec.yaml').read_text(encoding='utf-8'), re.M):
            command += ['--dart-define=ENV=prod']
        run(command, app)


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        print('blueprint: Python 3.11 or newer is required; no files were changed', file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create_parser = commands.add_parser('create')
    create_parser.add_argument('name')
    create_parser.add_argument('--output', required=True)
    create_parser.add_argument('--org', required=True)
    create_parser.add_argument('--platforms', default=','.join(PLATFORMS))
    create_parser.add_argument('--template', choices=tuple(TEMPLATES), default='minimal')
    create_parser.add_argument('--dry-run', action='store_true')
    feature_parser = commands.add_parser('feature')
    feature_parser.add_argument('path')
    feature_parser.add_argument('name')
    feature_parser.add_argument('--kind', choices=['presentation', 'api', 'local'], required=True)
    feature_parser.add_argument('--dry-run', action='store_true')
    module_parser = commands.add_parser('module')
    module_parser.add_argument('name')
    module_parser.add_argument('--workspace', required=True)
    module_parser.add_argument('--dry-run', action='store_true')
    validate_parser = commands.add_parser('validate')
    check_parser = commands.add_parser('check')
    check_parser.add_argument('phase', choices=['bootstrap', 'generate', 'generate-check', 'format', 'format-check', 'analyze', 'test', 'browser', 'coverage', 'architecture', 'ai'])
    for item in (validate_parser, check_parser):
        item.add_argument('--workspace', default=str(ROOT))
        item.add_argument('--coverage-min', type=float, default=80)
    build_parser = commands.add_parser('build')
    build_parser.add_argument('--app', required=True)
    build_parser.add_argument('--platforms', required=True)
    args = parser.parse_args(argv)
    try:
        globals()[args.command](args)
        return 0
    except (BlueprintError, OSError) as error:
        print(f'blueprint: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
