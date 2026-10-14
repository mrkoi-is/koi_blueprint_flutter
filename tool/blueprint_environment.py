"""Shared, read-only tool inventory for doctor and packaging adapters."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

TOOLS = {
    'inno': {'executable': 'iscc', 'env': 'BLUEPRINT_ISCC', 'host': 'win32', 'args': ['/?'], 'identity': r'Inno Setup', 'minimum': (6, 3, 3), 'maximum_major': 7},
    'dpkg': {'executable': 'dpkg-deb', 'env': 'BLUEPRINT_DPKG_DEB', 'host': 'linux', 'args': ['--version'], 'identity': r'dpkg-deb', 'minimum': (1, 19, 0), 'maximum_major': 1},
    'shlibdeps': {'executable': 'dpkg-shlibdeps', 'env': 'BLUEPRINT_DPKG_SHLIBDEPS', 'host': 'linux', 'args': ['--version'], 'identity': r'dpkg-shlibdeps', 'minimum': (1, 19, 0), 'maximum_major': 1},
    'appimagetool': {'executable': 'appimagetool', 'env': 'BLUEPRINT_APPIMAGETOOL', 'host': 'linux', 'args': ['--version'], 'identity': r'appimagetool', 'required_flags': ['--runtime-file']},
    'linuxdeploy': {'executable': 'linuxdeploy', 'env': 'BLUEPRINT_LINUXDEPLOY', 'host': 'linux', 'args': ['--version'], 'identity': r'linuxdeploy', 'required_flags': ['--appdir', '--executable']},
    'hdiutil': {'executable': 'hdiutil', 'env': 'BLUEPRINT_HDIUTIL', 'host': 'darwin', 'args': ['help'], 'identity': r'hdiutil'},
    'imagemagick': {'executable': 'magick', 'env': 'BLUEPRINT_MAGICK', 'args': ['-version'], 'identity': r'ImageMagick', 'minimum': (7, 1, 0), 'maximum_major': 7},
}
FORMATS = {'exe': ('inno',), 'deb': ('dpkg', 'shlibdeps'), 'AppImage': ('linuxdeploy', 'appimagetool'), 'dmg': ('hdiutil',), 'zip': (), 'apk': (), 'app': ()}
DEFAULT_FORMATS = {'web': 'zip', 'android': 'apk', 'ios': 'app', 'macos': 'dmg', 'windows': 'exe', 'linux': 'deb'}


def capture(command, cwd=None):
    result = subprocess.run([str(p) for p in command], cwd=cwd, capture_output=True, text=True, timeout=30)
    # ISCC /? historically returns 1; its identity and version are still checked.
    if result.returncode not in (0, 1):
        raise ValueError(f'Tool probe failed ({result.returncode}): {command[0]}')
    return result.stdout + result.stderr


def inspect_tool(key, *, host=None, env=None, which=None, probe=None):
    spec = TOOLS[key]
    env = os.environ if env is None else env
    which, probe = which or shutil.which, probe or capture
    result = {'tool': key, 'status': 'MISSING', 'environment': spec['env']}
    if spec.get('host') and spec['host'] != (host or sys.platform):
        return {**result, 'status': 'WRONG_HOST', 'requiredHost': spec['host']}
    executable = env.get(spec['env']) or which(spec['executable'])
    if not executable or not Path(executable).is_file():
        return result
    try:
        output = probe([executable, *spec['args']])
        if not re.search(spec['identity'], output, re.I):
            raise ValueError('Executable did not identify as the expected tool')
        version_match = re.search(r'(?<!\d)(\d+)\.(\d+)(?:\.(\d+))?', output)
        version = tuple(int(p or 0) for p in version_match.groups()) if version_match else None
        if spec.get('minimum') and (version is None or version < spec['minimum'] or version[0] > spec['maximum_major']):
            raise ValueError(f'Expected version >= {spec["minimum"]}, major <= {spec["maximum_major"]}')
        if spec.get('required_flags'):
            help_text = probe([executable, '--help'])
            if any(flag not in help_text for flag in spec['required_flags']):
                raise ValueError('Required command-line API is missing')
            if version is None and not re.search(r'(?:commit|version)[ :]+[a-f0-9]{7,40}', output, re.I):
                raise ValueError('Tool has no identifiable version or source commit')
        return {**result, 'status': 'AVAILABLE', 'executable': str(Path(executable).resolve()),
                'version': '.'.join(map(str, version)) if version else output.strip()[:300],
                'executableSha256': hashlib.sha256(Path(executable).read_bytes()).hexdigest()}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return {**result, 'status': 'UNSUPPORTED', 'reason': str(error)}


def packaging_tools(format_name, **kwargs):
    if format_name not in FORMATS:
        raise ValueError('Unknown package format')
    return [inspect_tool(key, **kwargs) for key in FORMATS[format_name]]


def require_packaging_tools(format_name):
    values = packaging_tools(format_name)
    failures = [item for item in values if item['status'] != 'AVAILABLE']
    if failures:
        raise ValueError('Packaging prerequisites: ' + '; '.join(f'{v["tool"]}: {v["status"]} (set {v["environment"]})' for v in failures))
    return {item['tool']: item for item in values}


def inspect_appimage_runtime(architecture=None, *, host=None, env=None):
    """Inspect the same pinned type-2 ELF input used by package, without running it."""
    result = {'tool': 'appimage-runtime', 'environment': 'BLUEPRINT_APPIMAGE_RUNTIME'}
    if (host or sys.platform) != 'linux':
        return {**result, 'status': 'WRONG_HOST', 'requiredHost': 'linux'}
    runtime = (os.environ if env is None else env).get(result['environment'])
    if not runtime or not Path(runtime).is_file():
        return {**result, 'status': 'MISSING'}
    path = Path(runtime).resolve()
    try:
        from tool.blueprint_build import binary_architectures, hash_file
        with path.open('rb') as stream:
            header = stream.read(20)
        if header[:4] != b'\x7fELF' or header[8:11] != b'AI\x02':
            raise ValueError('Pinned runtime must identify as a type-2 AppImage ELF')
        actual = binary_architectures(path)
        if len(actual) != 1 or actual[0] not in ('x64', 'arm64'):
            raise ValueError('Unsupported AppImage runtime architecture')
        if architecture is not None and actual != (architecture,):
            raise ValueError(f'Runtime architecture {actual[0]} differs from profile {architecture}')
        return {**result, 'status': 'AVAILABLE', 'path': str(path), 'sha256': hash_file(path),
                'actualArchitecture': actual[0]}
    except (OSError, ValueError) as error:
        return {**result, 'status': 'UNSUPPORTED', 'reason': str(error)}


def require_appimage_runtime(architecture):
    result = inspect_appimage_runtime(architecture)
    if result['status'] != 'AVAILABLE':
        raise ValueError(f'AppImage runtime: {result["status"]}; {result.get("reason", "set BLUEPRINT_APPIMAGE_RUNTIME to a pinned type-2 runtime")}')
    return result


def doctor_report(*, formats=(), branding=False, profiles=()):
    from tool.blueprint_config import validate_profile
    profiles = [validate_profile(profile) for profile in profiles]
    formats = list(dict.fromkeys([*formats, *[profile.get('format', DEFAULT_FORMATS[profile['platform']]) for profile in profiles]]))
    if any(format_name not in FORMATS for format_name in formats):
        raise ValueError('Unknown package format')
    keys = list(dict.fromkeys(key for fmt in formats for key in FORMATS[fmt]))
    if branding:
        keys.append('imagemagick')
    values = [inspect_tool(key) for key in dict.fromkeys(keys)]
    if 'AppImage' in formats:
        architectures = list(dict.fromkeys(profile['arch'] for profile in profiles if profile.get('format') == 'AppImage')) or [None]
        values.extend(inspect_appimage_runtime(architecture) for architecture in architectures)
    return {'schema': 1, 'host': sys.platform, 'tools': values,
            'status': 'PASS' if all(v['status'] == 'AVAILABLE' for v in values) else 'INCOMPLETE'}


def capability_doctor(app, capabilities, **kwargs):
    from tool.blueprint_capability_doctor import capability_doctor as diagnose
    return diagnose(app, capabilities, **kwargs)
