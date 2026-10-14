"""Actual host packaging adapters; preparation is isolated from verified builds."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

from tool.blueprint_environment import require_packaging_tools, require_appimage_runtime
from tool.blueprint_capability_doctor import (GSTREAMER_DEBIAN_PACKAGES,
    uses_audioplayers_linux, gstreamer_doctor, probe_gstreamer_runtime)


def _safe(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.+-]*', value):
        raise ValueError(f'Unsafe package identifier: {value!r}')
    return value


def _iss(value):
    if any(char in str(value) for char in '\r\n\0'):
        raise ValueError('Invalid installer path')
    return str(value).replace('{', '{{').replace('"', '""')


def _executable(source, platform):
    from tool.blueprint_build import binary_architectures
    files = [p for p in source.iterdir() if p.is_file() and not p.is_symlink()
             and (p.suffix.lower() == '.exe' if platform == 'windows' else os.access(p, os.X_OK) and binary_architectures(p))]
    if len(files) != 1:
        raise ValueError(f'Expected exactly one top-level {platform} executable, found {len(files)}')
    _safe(files[0].name)
    return files[0]


def _desktop(identifier, executable):
    return f'[Desktop Entry]\nType=Application\nName={identifier}\nExec={executable}\nIcon={identifier}\nTerminal=false\nCategories=Utility;\n'


def _icon(app, identifier, target):
    # Branding writes this stable input. Default is an explicit local-build icon.
    generated = app / 'assets/brand/icon.png'
    if generated.is_file():
        shutil.copy2(generated, target / (identifier + '.png'))
        return target / (identifier + '.png')
    icon = target / (identifier + '.svg')
    icon.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="48" fill="#315C80"/><path d="M64 64v128h32v-48l48 48h48l-64-64 64-64h-48l-48 48V64z" fill="white"/></svg>')
    return icon


def bundle_gstreamer(tree, tools, app, arch, run):
    """Collect the installed plugin set and fail closed on incomplete relocation."""
    from tool.blueprint_build import binary_architectures, hash_file
    prerequisites = gstreamer_doctor('linux')
    if prerequisites['status'] != 'PASS':
        raise ValueError(f'GStreamer AppImage prerequisites are not verified: {prerequisites}')
    pkg_config = shutil.which('pkg-config')
    if not pkg_config: raise ValueError('pkg-config is required to locate GStreamer runtime files')
    locations, commands = {}, []
    for key in ('pluginsdir', 'pluginscannerdir'):
        command = [pkg_config, '--variable=' + key, 'gstreamer-1.0']
        commands.append(command)
        result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=10)
        value = result.stdout.strip()
        if not value or not Path(value).is_absolute() or not Path(value).is_dir():
            raise ValueError(f'GStreamer {key} is not an existing absolute directory')
        locations[key] = Path(value).resolve()
    plugins = sorted(path for path in locations['pluginsdir'].glob('*.so*') if path.is_file())
    if not plugins: raise ValueError('No GStreamer plugins to bundle')
    scanner = locations['pluginscannerdir'] / 'gst-plugin-scanner'
    files = [(path, tree / 'usr/lib/gstreamer-1.0' / path.name) for path in plugins]
    files.append((scanner, tree / 'usr/libexec/gstreamer-1.0/gst-plugin-scanner'))
    origins = []
    for source, target in files:
        if not source.is_file() or binary_architectures(source) != (arch,):
            raise ValueError(f'GStreamer runtime file is missing or has the wrong architecture: {source}')
        if source == scanner and not os.access(source, os.X_OK):
            raise ValueError('GStreamer scanner is not executable')
        digest = hash_file(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target, follow_symlinks=True)
        if hash_file(target) != digest or hash_file(source) != digest:
            raise ValueError('GStreamer host input changed while copying: ' + str(source))
        origins.append({'source': str(source), 'sourceSha256': digest,
                        'path': target.relative_to(tree).as_posix()})
    command = [tools['linuxdeploy']['executable'], '--appdir', tree,
               '--executable', files[-1][1]]
    for _, target in files[:-1]: command += ['--library', target]
    run(command, app)
    plugin_dir = tree / 'usr/lib/gstreamer-1.0'
    scanner_target = files[-1][1]
    environment = {
        'LD_LIBRARY_PATH': str(tree / 'usr/lib'),
        'GST_PLUGIN_PATH': str(plugin_dir), 'GST_PLUGIN_PATH_1_0': str(plugin_dir),
        'GST_PLUGIN_SYSTEM_PATH': '', 'GST_PLUGIN_SYSTEM_PATH_1_0': '',
        'GST_PLUGIN_SCANNER': str(scanner_target), 'GST_PLUGIN_SCANNER_1_0': str(scanner_target),
        'GST_REGISTRY': str(tree.parent / 'gst-verify-registry.bin'),
        'GST_REGISTRY_1_0': str(tree.parent / 'gst-verify-registry.bin'),
        'BLUEPRINT_GSTREAMER_PLUGINS': str(plugin_dir),
    }
    for _, target in files:
        if not target.is_file() or not target.resolve().is_relative_to(tree.resolve()):
            raise ValueError('GStreamer bundler left a missing or external file: ' + str(target))
    ldd = shutil.which('ldd')
    if not ldd: raise ValueError('ldd is required to verify the bundled GStreamer scanner')
    scanner_command = [ldd, str(scanner_target)]
    scanner_check = subprocess.run(scanner_command, capture_output=True, text=True,
        timeout=10, env={**os.environ, **environment})
    if scanner_check.returncode or 'not found' in (scanner_check.stdout + scanner_check.stderr).lower():
        raise ValueError('Bundled GStreamer scanner has unresolved dependencies: ' + scanner_check.stdout + scanner_check.stderr)
    runtime = probe_gstreamer_runtime(environment_overrides=environment)
    if runtime.get('status') != 'LOADABLE':
        raise ValueError(f'Bundled GStreamer plugins cannot load: {runtime}')
    expected = {str(target.resolve()) for _, target in files[:-1]}
    if set(runtime.get('verifiedPlugins', [])) != expected:
        raise ValueError('GStreamer plugin closure was not fully verified')
    for item in runtime.get('libraries', []) + runtime.get('elementPlugins', []):
        if not Path(item['path']).resolve().is_relative_to(tree.resolve()):
            raise ValueError('GStreamer verification fell back to a host library/plugin: ' + item['path'])
    if {item.get('soname') for item in runtime.get('libraries', [])} != {'libgstreamer-1.0.so.0', 'libgstapp-1.0.so.0', 'libgstaudio-1.0.so.0'} or {item.get('element') for item in runtime.get('elementPlugins', [])} != {'playbin', 'audioconvert', 'audioresample', 'wavparse', 'autoaudiosink', 'audiopanorama'}:
        raise ValueError('Incomplete GStreamer runtime verification evidence')
    for origin in origins:
        if hash_file(Path(origin['source'])) != origin['sourceSha256']:
            raise ValueError('GStreamer host input changed during packaging: ' + origin['source'])
        origin['bundledSha256'] = hash_file(tree / origin['path'])
    return {'status': 'VERIFIED', 'prerequisites': prerequisites, 'discoveryCommands': commands,
            'scannerDependencyCheck': {'command': scanner_command, 'output': scanner_check.stdout},
            'files': origins, 'runtime': runtime,
            'limitation': 'Plugin loading verified; audio output, codecs beyond the bundled host set and installation require target acceptance'}


def package_native(format_name, source, stage, app, manifest, stem, run):
    """Return exact tool identities; callers hash output after this succeeds."""
    gstreamer = manifest['profile']['platform'] == 'linux' and uses_audioplayers_linux(app)
    tools = require_packaging_tools(format_name)
    profile = manifest['profile']
    identifier = _safe(app.name.replace('_', '-').lower())
    version = _safe(manifest['version'])
    if not version[0].isdigit():
        raise ValueError('Package version must start with a digit')
    work = stage / '.work'
    work.mkdir()
    try:
        if format_name == 'exe':
            executable = _executable(source, 'windows')
            script = work / 'installer.iss'
            arch = 'x64compatible' if profile['arch'] == 'x64' else 'arm64'
            app_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, identifier))
            script.write_text(f'''[Setup]
AppId={{{{{app_id}}}
AppName={identifier}
AppVersion={version}
DefaultDirName={{localappdata}}\\Programs\\{identifier}
DefaultGroupName={identifier}
PrivilegesRequired=lowest
ArchitecturesAllowed={arch}
ArchitecturesInstallIn64BitMode={arch}
OutputDir={_iss(stage)}
OutputBaseFilename={_safe(stem)}
Compression=lzma2
SolidCompression=yes
Uninstallable=yes
[Files]
Source: "{_iss(source)}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\\{identifier}"; Filename: "{{app}}\\{_iss(executable.name)}"
''', encoding='utf-8')
            run([tools['inno']['executable'], '/Qp', script], app)
            output = stage / (stem + '.exe')
            if not output.is_file() or output.read_bytes()[:2] != b'MZ':
                raise ValueError('Inno Setup did not produce a PE installer')
        elif format_name in ('deb', 'AppImage'):
            executable = _executable(source, 'linux')
            tree = work / ('package' if format_name == 'deb' else identifier + '.AppDir')
            payload = tree / 'usr/lib' / identifier
            payload.parent.mkdir(parents=True)
            shutil.copytree(source, payload, symlinks=True)
            launcher = tree / 'usr/bin' / identifier
            launcher.parent.mkdir(parents=True)
            launcher.write_text(f'#!/bin/sh\nexec /usr/lib/{identifier}/{executable.name} "$@"\n')
            launcher.chmod(0o755)
            desktop = tree / 'usr/share/applications' / (identifier + '.desktop')
            desktop.parent.mkdir(parents=True)
            desktop.write_text(_desktop(identifier, identifier))
            icons = tree / 'usr/share/icons/hicolor/256x256/apps'
            icons.mkdir(parents=True)
            icon = _icon(app, identifier, icons)
            if format_name == 'deb':
                control = tree / 'DEBIAN'
                control.mkdir()
                debian = work / 'debian'
                debian.mkdir()
                (debian / 'control').write_text(f'Source: {identifier}\nSection: utils\nPriority: optional\nMaintainer: Blueprint Local Build\n\nPackage: {identifier}\nArchitecture: any\nDescription: Local Flutter application\n')
                # All plugin/engine libraries matter, including dynamically loaded ones.
                from tool.blueprint_build import binary_architectures
                binaries = [p for p in payload.rglob('*') if p.is_file() and not p.is_symlink() and binary_architectures(p)]
                command = [tools['shlibdeps']['executable'], '-O', '--ignore-missing-info', '-l' + str(payload / 'lib'), *['-e' + str(p) for p in binaries]]
                result = subprocess.run(command, cwd=work, capture_output=True, text=True, check=True, timeout=60)
                dependency = next((line.removeprefix('shlibs:Depends=') for line in result.stdout.splitlines() if line.startswith('shlibs:Depends=')), '')
                if not dependency:
                    raise ValueError('dpkg-shlibdeps did not determine runtime dependencies')
                if '\n' in dependency or '\r' in dependency:
                    raise ValueError('Invalid dependency output')
                required = list(GSTREAMER_DEBIAN_PACKAGES) if gstreamer else []
                inferred = [item.strip() for item in dependency.split(',')]
                for name in required:
                    if not any('|' not in item and re.match(re.escape(name) + r'(?:\s|:|$)', item) for item in inferred):
                        inferred.append(name)
                dependency = ', '.join(inferred)
                tools['dependencyAnalysis'] = {'command': command, 'depends': dependency,
                    'explicitRuntimePackages': required,
                    'reason': 'audioplayers uses dynamically loaded GStreamer plugins' if gstreamer else 'ELF dependencies only'}
                architecture = {'x64': 'amd64', 'arm64': 'arm64'}[profile['arch']]
                control.joinpath('control').write_text(f'Package: {identifier}\nVersion: {version}\nArchitecture: {architecture}\nMaintainer: Blueprint Local Build\nDepends: {dependency}\nDescription: {identifier} local Flutter application\n')
                run([tools['dpkg']['executable'], '--build', '--root-owner-group', tree, stage / (stem + '.deb')], app)
                if (stage / (stem + '.deb')).read_bytes()[:8] != b'!<arch>\n':
                    raise ValueError('dpkg-deb did not produce a Debian archive')
            else:
                runtime_evidence = require_appimage_runtime(profile['arch'])
                runtime = Path(runtime_evidence['path'])
                # linuxdeploy discovers/bundles ELF dependencies rather than shipping only Flutter output.
                run([tools['linuxdeploy']['executable'], '--appdir', tree, '--executable', payload / executable.name, '--desktop-file', desktop, '--icon-file', icon], app)
                if gstreamer:
                    tools['gstreamer'] = bundle_gstreamer(tree, tools, app, profile['arch'], run)
                # Explicit relocatable entry remains independent of host installation paths.
                gst_environment = ('export GST_PLUGIN_PATH="$HERE/usr/lib/gstreamer-1.0"\n'
                    'export GST_PLUGIN_PATH_1_0="$GST_PLUGIN_PATH"\n'
                    'export GST_PLUGIN_SYSTEM_PATH="" GST_PLUGIN_SYSTEM_PATH_1_0=""\n'
                    'export GST_PLUGIN_SCANNER="$HERE/usr/libexec/gstreamer-1.0/gst-plugin-scanner"\n'
                    'export GST_PLUGIN_SCANNER_1_0="$GST_PLUGIN_SCANNER"\n'
                    'export GST_REGISTRY=/dev/null GST_REGISTRY_1_0=/dev/null GST_REGISTRY_UPDATE=no\n') if gstreamer else ''
                tree.joinpath('AppRun').write_text(f'#!/bin/sh\nHERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexport LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib/{identifier}/lib${{LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}}"\n{gst_environment}exec "$HERE/usr/lib/{identifier}/{executable.name}" "$@"\n')
                tree.joinpath('AppRun').chmod(0o755)
                for item in (desktop, icon):
                    destination = tree / item.name
                    if destination.exists() or destination.is_symlink():
                        destination.unlink()
                    shutil.copy2(item, destination)
                dir_icon = tree / '.DirIcon'
                if dir_icon.exists() or dir_icon.is_symlink():
                    dir_icon.unlink()
                dir_icon.symlink_to(icon.name)
                output = stage / (stem + '.AppImage')
                run([tools['appimagetool']['executable'], '--runtime-file', Path(runtime), tree, output], app)
                with output.open('rb') as stream:
                    header = stream.read(11)
                if header[:4] != b'\x7fELF' or header[8:11] != b'AI\x02':
                    raise ValueError('appimagetool did not produce a type-2 AppImage')
                output.chmod(output.stat().st_mode | 0o111)
                from tool.blueprint_build import hash_file
                if hash_file(runtime) != runtime_evidence['sha256']:
                    raise ValueError('Pinned AppImage runtime changed during packaging')
                tools['runtime'] = runtime_evidence
        else:
            raise ValueError('Unsupported native package adapter')
        return tools
    finally:
        shutil.rmtree(work)
