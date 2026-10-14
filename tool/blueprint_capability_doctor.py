"""Read-only capability diagnosis; asset presence is never a runtime verdict."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from tool.blueprint_capabilities import catalog, resolve, safe_file
from tool.blueprint_provenance import read_metadata

GSTREAMER_MODULES = ('gstreamer-1.0', 'gstreamer-app-1.0', 'gstreamer-audio-1.0')
GSTREAMER_DEBIAN_PACKAGES = ('libgstreamer1.0-0', 'libgstreamer-plugins-base1.0-0',
                           'gstreamer1.0-plugins-base', 'gstreamer1.0-plugins-good')


def uses_audioplayers_linux(app):
    """Inspect this App, not a workspace lock shared with unrelated Apps."""
    app = Path(app)
    pubspec = app / 'pubspec.yaml'
    if pubspec.is_file():
        in_dependencies = False
        for line in pubspec.read_text(encoding='utf-8').splitlines():
            if line and not line[0].isspace() and not line.startswith('#'):
                in_dependencies = bool(re.fullmatch(r'dependencies:\s*(?:#.*)?', line))
            if in_dependencies and re.match(r'''^  ["']?audioplayers(?:_linux)?["']?\s*:''', line):
                return True
    plugins = app / '.flutter-plugins-dependencies'
    if plugins.is_file():
        # The App's resolved plugin list also catches a transitive installation.
        data = json.loads(plugins.read_text(encoding='utf-8'))
        return any(item.get('name') == 'audioplayers_linux'
                   for item in data.get('plugins', {}).get('linux', []))
    return False


_GSTREAMER_PROBE = r'''
import ctypes, glob, hashlib, json, os
names = ('libgstreamer-1.0.so.0', 'libgstapp-1.0.so.0', 'libgstaudio-1.0.so.0')
libraries = [ctypes.CDLL(name) for name in names]
gst = libraries[0]
gst.gst_init_check.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
gst.gst_init_check.restype = ctypes.c_int
error = ctypes.c_void_p()
if not gst.gst_init_check(None, None, ctypes.byref(error)):
    raise RuntimeError('gst_init_check failed')
gst.gst_version_string.restype = ctypes.c_char_p
gst.gst_element_factory_make.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
gst.gst_element_factory_make.restype = ctypes.c_void_p
gst.gst_object_unref.argtypes = [ctypes.c_void_p]
elements = ('playbin', 'audioconvert', 'audioresample', 'wavparse', 'autoaudiosink', 'audiopanorama')
gst.gst_element_get_factory.argtypes = [ctypes.c_void_p]
gst.gst_element_get_factory.restype = ctypes.c_void_p
gst.gst_plugin_feature_get_plugin.argtypes = [ctypes.c_void_p]
gst.gst_plugin_feature_get_plugin.restype = ctypes.c_void_p
gst.gst_plugin_get_filename.argtypes = [ctypes.c_void_p]
gst.gst_plugin_get_filename.restype = ctypes.c_char_p
gst.gst_plugin_load_file.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
gst.gst_plugin_load_file.restype = ctypes.c_void_p
verified_plugins = []
explicit_plugins = os.environ.get('BLUEPRINT_GSTREAMER_PLUGINS')
if explicit_plugins:
    for path in sorted(glob.glob(os.path.join(explicit_plugins, '*.so*'))):
        plugin = gst.gst_plugin_load_file(os.fsencode(path), ctypes.byref(error))
        if not plugin: raise RuntimeError('Bundled plugin cannot load: ' + path)
        verified_plugins.append(os.path.realpath(path))
        gst.gst_object_unref(plugin)
element_plugins = []
for name in elements:
    element = gst.gst_element_factory_make(name.encode(), None)
    if not element: raise RuntimeError('Missing/unloadable GStreamer element: ' + name)
    plugin = gst.gst_plugin_feature_get_plugin(gst.gst_element_get_factory(element))
    if not plugin: raise RuntimeError('Cannot identify element plugin: ' + name)
    filename = gst.gst_plugin_get_filename(plugin)
    if not filename: raise RuntimeError('Element has no verifiable plugin file: ' + name)
    element_plugins.append({'element': name, 'path': os.path.realpath(os.fsdecode(filename))})
    gst.gst_object_unref(plugin)
    gst.gst_object_unref(element)
mapped = set()
with open('/proc/self/maps') as source:
    for line in source:
        parts = line.rstrip().split(None, 5)
        if len(parts) == 6 and os.path.isfile(parts[5]): mapped.add(parts[5])
loaded = []
for name in names:
    paths = sorted(path for path in mapped if os.path.basename(path).startswith(name))
    if not paths: raise RuntimeError('Cannot identify loaded library: ' + name)
    for path in paths:
        with open(path, 'rb') as source: digest = hashlib.sha256(source.read()).hexdigest()
        loaded.append({'soname': name, 'path': path, 'sha256': digest})
print(json.dumps({'status': 'LOADABLE', 'version': gst.gst_version_string().decode(),
                  'libraries': loaded, 'elements': list(elements), 'elementPlugins': element_plugins,
                  'verifiedPlugins': verified_plugins,
                  'operation': 'gst_init_check and element factory creation; no playback'}))
'''


def probe_gstreamer_runtime(*, environment_overrides=None):
    environment = dict(os.environ)
    # Probe existing host libraries/plugins without modifying the user's registry.
    environment['GST_REGISTRY_UPDATE'] = 'no'
    environment.update(environment_overrides or {})
    try:
        process = subprocess.run([sys.executable, '-c', _GSTREAMER_PROBE],
                                 capture_output=True, text=True, timeout=20, env=environment)
        if process.returncode:
            return {'status': 'NOT_LOADABLE', 'exitCode': process.returncode,
                    'reason': (process.stderr or process.stdout).strip()[-1200:]}
        return json.loads(process.stdout.strip().splitlines()[-1])
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return {'status': 'NOT_LOADABLE', 'reason': str(error)}


def gstreamer_doctor(host):
    base = {'platform': 'linux', 'capability': 'system-media', 'engine': 'audioplayers',
            'debianPackages': list(GSTREAMER_DEBIAN_PACKAGES)}
    if host != 'linux':
        return {**base, 'status': 'NOT_RUN', 'reason': 'GStreamer build/runtime verification requires Linux'}
    pkg_config = shutil.which('pkg-config')
    modules = []
    for module in GSTREAMER_MODULES:
        command = [pkg_config or 'pkg-config', '--modversion', module]
        try:
            if not pkg_config: raise FileNotFoundError('pkg-config is not installed')
            process = subprocess.run(command, capture_output=True, text=True, timeout=10)
            version = process.stdout.strip()
            valid = process.returncode == 0 and re.fullmatch(r'1\.\d+(?:\.\d+)*(?:[-+][\w.-]+)?', version)
            modules.append({'module': module, 'command': command, 'version': version,
                            'status': 'FOUND' if valid else 'MISSING_OR_INCOMPATIBLE',
                            'exitCode': process.returncode, 'reason': process.stderr.strip()[-1200:]})
        except (OSError, subprocess.SubprocessError) as error:
            modules.append({'module': module, 'command': command, 'status': 'MISSING_OR_INCOMPATIBLE', 'reason': str(error)})
    # Installed .pc metadata is not evidence that runtime libraries can load.
    runtime = probe_gstreamer_runtime()
    return {**base, 'status': 'PASS' if all(item['status'] == 'FOUND' for item in modules)
            and runtime.get('status') == 'LOADABLE' else 'FAIL',
            'buildModules': modules, 'runtime': runtime,
            'limitation': 'Host prerequisite check only; App playback and installation require separate target validation'}

# Probe in a child process: a malformed native library must not kill the CLI.
_NATIVE_PROBE = r'''
import ctypes, json, os, sys
search_handles = []
if sys.platform == 'win32':
    search_handles = [os.add_dll_directory(path) for path in json.loads(sys.argv[3])]
library = ctypes.CDLL(sys.argv[2])
if sys.argv[1] == 'sqlite':
    library.sqlite3_libversion.restype = ctypes.c_char_p
    library.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    library.sqlite3_close.argtypes = [ctypes.c_void_p]
    library.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    handle = ctypes.c_void_p()
    opened = library.sqlite3_open(b':memory:', ctypes.byref(handle))
    try:
        if opened != 0: raise RuntimeError('sqlite3_open failed: %s' % opened)
        code = library.sqlite3_exec(handle, b'CREATE TABLE doctor(value INTEGER); INSERT INTO doctor VALUES(1); SELECT * FROM doctor;', None, None, None)
        if code != 0: raise RuntimeError('sqlite3_exec failed: %s' % code)
        version = library.sqlite3_libversion().decode()
    finally:
        if handle: library.sqlite3_close(handle)
elif sys.argv[1] == 'media':
    library.mpv_client_api_version.restype = ctypes.c_ulong
    library.mpv_create.restype = ctypes.c_void_p
    library.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    library.mpv_initialize.argtypes = [ctypes.c_void_p]
    library.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
    handle = library.mpv_create()
    if not handle: raise RuntimeError('mpv_create failed')
    try:
        for key in (b'vo', b'ao'):
            if library.mpv_set_option_string(handle, key, b'null') < 0: raise RuntimeError('mpv null output setup failed')
        code = library.mpv_initialize(handle)
        if code < 0: raise RuntimeError('mpv_initialize failed: %s' % code)
        version = str(library.mpv_client_api_version())
    finally:
        library.mpv_terminate_destroy(handle)
else: raise RuntimeError('Unknown library kind')
print(json.dumps({'status': 'LOADABLE', 'libraryVersion': version, 'operation': 'in-memory SQL' if sys.argv[1] == 'sqlite' else 'headless engine initialization'}))
'''


def workspace_root(app):
    for parent in (Path(app).resolve(), *Path(app).resolve().parents):
        if (parent / 'pubspec.lock').is_file() or (parent / 'blueprint.json').is_file():
            return parent
    return Path(app).resolve()


def locked_versions(root):
    path = Path(root) / 'pubspec.lock'
    if not path.is_file(): return {}
    values = {}
    for match in re.finditer(r'^  ([a-zA-Z0-9_]+):\s*\n((?:    .*\n|\n)*)', path.read_text(), re.M):
        version = re.search(r'^    version:\s*[\'"]?([^\'"\s]+)', match[2], re.M)
        if version: values[match[1]] = version[1]
    return values


def matches_version(version, constraint):
    if not constraint.startswith('^'): return version == constraint
    def parse(value):
        match = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)(?:\+[a-zA-Z0-9.]+)?', value)
        return tuple(map(int, match.groups())) if match else None
    actual, minimum = parse(version), parse(constraint[1:])
    if actual is None or minimum is None: return False
    upper = (minimum[0] + 1, 0, 0) if minimum[0] else ((0, minimum[1] + 1, 0) if minimum[1] else (0, 0, minimum[2] + 1))
    return minimum <= actual < upper


def probe_native_library(kind, path):
    path = Path(path).resolve()
    search = [str(path.parent)]
    frameworks = next((parent for parent in path.parents if parent.name == 'Frameworks'), None)
    if frameworks: search.insert(0, str(frameworks))
    environment = dict(os.environ)
    # Match the App's local loader roots without mutating the App or loading an
    # unrelated system copy. This also resolves @rpath companion frameworks.
    for key in ('DYLD_FRAMEWORK_PATH', 'DYLD_LIBRARY_PATH', 'LD_LIBRARY_PATH'):
        environment[key] = os.pathsep.join(search + ([environment[key]] if environment.get(key) else []))
    result = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'loaderSearchPaths': search}
    try:
        process = subprocess.run([sys.executable, '-c', _NATIVE_PROBE, kind, str(path), json.dumps(search)], capture_output=True, text=True, timeout=20, env=environment)
        if process.returncode != 0:
            return {**result, 'status': 'NOT_LOADABLE', 'reason': (process.stderr or process.stdout).strip()[-1200:], 'exitCode': process.returncode}
        return {**result, **json.loads(process.stdout.strip().splitlines()[-1])}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return {**result, 'status': 'NOT_LOADABLE', 'reason': str(error)}


def native_candidates(app, target, kind):
    # App-owned build products only: a system library does not prove the App links.
    app = Path(app)
    roots = [app / 'build/native_assets' / target]
    # Intermediate SDK/XCFramework copies are deliberately not App runtime evidence.
    if target == 'macos': roots += list((app / 'build/macos/Build/Products').glob('*/*.app'))
    elif target == 'windows': roots += list((app / 'build/windows').glob('*/runner/*'))
    elif target == 'linux': roots += list((app / 'build/linux').glob('*/*/bundle'))
    candidates = []
    for root in roots:
        if not root.exists(): continue
        for path in root.rglob('*'):
            if not path.is_file(): continue
            name = path.name.lower()
            native = name.endswith(('.dll', '.dylib', '.so')) or '.so.' in name or '.framework/' in path.as_posix()
            if native and (('sqlite3' in name) if kind == 'sqlite' else ('mpv' in name)):
                candidates.append(path.resolve())
    return sorted(set(candidates))


def web_database_assets(app, versions):
    manifest = Path(app) / 'web/drift-assets.json'
    result = {'platform': 'web', 'capability': 'database', 'runtime': 'NOT_RUN',
              'runtimeReason': 'Browser SQLite initialization and worker execution require the browser gate'}
    if not manifest.is_file(): return {**result, 'status': 'MISSING', 'reason': 'web/drift-assets.json missing'}
    try:
        data = json.loads(manifest.read_text())
        for dependency in ('drift', 'sqlite3'):
            if data.get(dependency) != versions.get(dependency): raise ValueError(f'{dependency} Web asset version differs from pubspec.lock')
        entries = data.get('assets', [])
        if {entry['path'] for entry in entries} != {'sqlite3.wasm', 'drift_worker.dart.js'} or len(entries) != 2:
            raise ValueError('Expected exactly SQLite WASM and drift worker assets')
        values = []
        for entry in entries:
            path = safe_file(manifest.parent, entry['path'])
            content = path.read_bytes()
            digest = hashlib.sha256(content).hexdigest()
            if digest != entry['sha256'] or len(content) != entry['size']: raise ValueError(f'{entry["path"]} content hash/size mismatch')
            if path.suffix == '.wasm' and content[:8] != b'\0asm\x01\0\0\0': raise ValueError('SQLite asset is not a WebAssembly module')
            values.append({'path': str(path), 'sha256': digest, 'size': len(content), 'source': entry.get('source')})
        return {**result, 'status': 'VERIFIED_ASSETS', 'versions': {key: data[key] for key in ('drift', 'sqlite3')}, 'assets': values}
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {**result, 'status': 'INVALID', 'reason': str(error)}


def capability_doctor(app, capabilities, *, host=None, platforms=None, entries=None, probe=None):
    app = Path(app).resolve()
    root = workspace_root(app)
    host = host or sys.platform
    metadata = read_metadata(root) or {}
    platforms = platforms if platforms is not None else metadata.get('platforms') or [key for key in ('web', 'android', 'ios', 'macos', 'windows', 'linux') if (app / key).is_dir()]
    if entries is None:
        catalog_root = root if (root / 'tool/capabilities/catalog.json').is_file() else Path(__file__).resolve().parent.parent
        entries = catalog(catalog_root)
    selected = resolve(list(capabilities), entries)
    versions = locked_versions(root)
    dependencies = []
    for key in selected:
        entry = entries[key]
        expected = {**entry.get('pubspecDependencies', {}), **entry.get('pubspecDevDependencies', {})}
        for dependency, constraint in expected.items():
            actual = versions.get(dependency)
            dependencies.append({'capability': key, 'dependency': dependency, 'constraint': constraint, 'version': actual,
                                 'status': 'MATCH' if actual and matches_version(actual, constraint) else 'MISMATCH'})
    libraries, assets = [], []
    kinds = []
    if 'database' in selected: kinds.append(('database', 'sqlite'))
    if 'system-media' in selected or 'mini-player' in selected: kinds.append(('system-media', 'media'))
    host_target = {'darwin': 'macos', 'linux': 'linux', 'win32': 'windows'}.get(host)
    for target in platforms:
        for capability, kind in kinds:
            if target == 'web' and kind == 'sqlite': assets.append(web_database_assets(app, versions))
            base = {'platform': target, 'capability': capability}
            if target != host_target:
                libraries.append({**base, 'status': 'NOT_RUN', 'reason': 'Browser gate required' if target == 'web' else f'Runtime verification requires {target} target; current host is {host}'})
                continue
            paths = native_candidates(app, target, kind)
            if not paths:
                libraries.append({**base, 'status': 'NOT_RUN', 'reason': 'No App-owned native library build product; build the target first'})
            else:
                results = [(probe or probe_native_library)(kind, path) for path in paths]
                libraries.append({**base, 'status': 'LOADABLE' if all(item['status'] == 'LOADABLE' for item in results) else 'NOT_LOADABLE', 'libraries': results,
                                  'limitation': 'Headless loading only; device, playback and target installation acceptance remain separate'})
    system_dependencies = [gstreamer_doctor(host)] if 'linux' in platforms and uses_audioplayers_linux(app) else []
    failed = any(v['status'] == 'MISMATCH' for v in dependencies) or any(v['status'] == 'NOT_LOADABLE' for v in libraries) or any(v['status'] != 'VERIFIED_ASSETS' for v in assets) or any(v['status'] == 'FAIL' for v in system_dependencies)
    incomplete = any(v['status'] == 'NOT_RUN' for v in libraries + system_dependencies)
    return {'schema': 1, 'app': str(app), 'host': host, 'capabilities': selected,
            'dependencies': dependencies, 'nativeLibraries': libraries, 'webAssets': assets, 'systemDependencies': system_dependencies,
            'status': 'FAIL' if failed else 'INCOMPLETE' if incomplete else 'PASS'}
