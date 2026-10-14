"""Target-owned builds and manifests. No publication or host installation."""
from __future__ import annotations

import hashlib
import os
import platform as host_platform
import json
from pathlib import Path
import re
import shutil
import struct
import sys
import zipfile
import tempfile

from tool.blueprint_config import digest, validate_profile
from tool.blueprint_provenance import read_metadata, source_identity
from tool.platform_evidence import source_manifest


def hash_file(path):
    hasher = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def describe_artifact(path, root):
    path, root = Path(path), Path(root)
    if not path.exists():
        raise ValueError(f'Required build artifact is missing: {path}')
    if path.is_file():
        return {'path': path.relative_to(root).as_posix(), 'size': path.stat().st_size, 'sha256': hash_file(path)}
    files = {}
    size = 0
    for file in sorted(path.rglob('*')):
        relative = file.relative_to(path).as_posix()
        if file.is_symlink():
            if not file.resolve().is_relative_to(path.resolve()):
                raise ValueError(f'Artifact symlink escapes bundle: {file}')
            files[relative] = {'link': str(file.readlink())}
        elif file.is_file():
            files[relative] = {'size': file.stat().st_size, 'sha256': hash_file(file)}
            size += file.stat().st_size
    if not files:
        raise ValueError(f'Required artifact directory is empty: {path}')
    return {'path': path.relative_to(root).as_posix(), 'size': size, 'treeSha256': digest(files), 'files': files}


def binary_architectures(path):
    with Path(path).open('rb') as stream:
        header = stream.read(4096)
    if header[:4] == b'\x7fELF':
        if len(header) < 20 or header[5] not in (1, 2):
            raise ValueError('Invalid ELF header')
        endian = '<' if header[5] == 1 else '>'
        code = struct.unpack_from(endian + 'H', header, 18)[0]
        return {62: 'x64', 183: 'arm64'}.get(code, f'elf-{code}'),
    if header[:2] == b'MZ':
        if len(header) < 64:
            raise ValueError('Invalid PE header')
        offset = struct.unpack_from('<I', header, 60)[0]
        with Path(path).open('rb') as stream:
            stream.seek(offset)
            signature = stream.read(6)
        if len(signature) < 6 or signature[:4] != b'PE\0\0':
            raise ValueError('Invalid PE signature')
        code = struct.unpack_from('<H', signature, 4)[0]
        return {0x8664: 'x64', 0xaa64: 'arm64'}.get(code, f'pe-{code}'),
    cpu_names = {0x01000007: 'x86_64', 0x0100000c: 'arm64'}
    if header[:4] in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
        if len(header) < 8:
            raise ValueError('Invalid Mach-O header')
        endian = '<' if header[:4] == b'\xcf\xfa\xed\xfe' else '>'
        code = struct.unpack_from(endian + 'I', header, 4)[0]
        return cpu_names.get(code, f'macho-{code}'),
    if header[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        if len(header) < 8:
            raise ValueError('Invalid Mach-O architecture table')
        count = struct.unpack_from('>I', header, 4)[0]
        stride = 32 if header[3] == 0xbf else 20
        if count > 32 or 8 + count * stride > len(header):
            raise ValueError('Invalid Mach-O architecture table')
        return tuple(cpu_names.get(struct.unpack_from('>I', header, 8 + i * stride)[0], 'unknown') for i in range(count))
    return ()


def verify_architecture(path, platform, arch):
    path = Path(path)
    if platform == 'web':
        if not (path / 'index.html').is_file() or not (path / 'flutter_bootstrap.js').is_file():
            raise ValueError('Incomplete Web bundle')
        return ['web']
    if platform == 'android':
        with zipfile.ZipFile(path) as archive:
            libraries = [name for name in archive.namelist() if re.fullmatch(r'lib/[^/]+/[^/]+\.so', name)]
            abis = sorted({name.split('/')[1] for name in libraries})
            if abis != [arch]:
                raise ValueError(f'APK must contain only requested ABI {arch}: {abis}')
            machine = {'arm64-v8a': 183, 'armeabi-v7a': 40, 'x86_64': 62}[arch]
            for name in libraries:
                with archive.open(name) as stream:
                    header = stream.read(20)
                if len(header) < 20 or header[:4] != b'\x7fELF' or header[5] not in (1, 2):
                    raise ValueError(f'APK has invalid native library: {name}')
                actual = struct.unpack_from(('<' if header[5] == 1 else '>') + 'H', header, 18)[0]
                if actual != machine:
                    raise ValueError(f'APK native binary contradicts its ABI directory: {name}')
        return abis
    found = []
    files = path.rglob('*') if path.is_dir() else [path]
    for file in files:
        if not file.is_file() or file.is_symlink():
            continue
        actual = binary_architectures(file)
        if actual:
            if set(actual) != {arch}:
                raise ValueError(f'Native artifact missing {arch}: {file}: {actual}')
            found.extend(actual)
    if not found:
        raise ValueError('No native executable/library architecture could be verified')
    return sorted(set(found))


def artifact_path(app, profile):
    target, mode = profile['platform'], profile['mode']
    direct = {'web': app / 'build/web', 'android': app / f'build/app/outputs/flutter-apk/app-{mode}.apk',
              'linux': app / f'build/linux/{profile["arch"]}/{mode}/bundle',
              'windows': app / f'build/windows/{profile["arch"]}/runner/{mode.title()}'}
    if target in direct:
        return direct[target]
    directory = app / ('build/ios/iphoneos' if target == 'ios' else f'build/macos/Build/Products/{mode.title()}')
    apps = list(directory.glob('*.app'))
    if len(apps) != 1:
        raise ValueError(f'Expected exactly one application in {directory}')
    return apps[0]


_ABI_SNIPPET = '''
        // -PkoiAbi is the profile ABI. Flutter otherwise leaves every default plugin ABI in the APK.
        // Bind a non-null String before the ndk lambda; the script compiler will not smart-cast into it.
        val requested = project.findProperty("koiAbi") as? String
        if (requested == "arm64-v8a" || requested == "armeabi-v7a" || requested == "x86_64") {
            val abi: String = requested
            ndk {
                abiFilters.clear()
                abiFilters.add(abi)
            }
        }'''


def ensure_android_abi_filter(app):
    """Keep plugin JNI inside the requested ABI after Flutter resets abiFilters."""
    gradle = Path(app) / 'android/app/build.gradle.kts'
    if not gradle.is_file():
        return
    text = gradle.read_text(encoding='utf-8')
    if 'val abi: String = requested' in text:
        return
    anchor = 'versionName = flutter.versionName'
    if anchor not in text:
        raise ValueError('Android build.gradle.kts has no versionName anchor for ABI filtering')
    gradle.write_text(text.replace(anchor, anchor + _ABI_SNIPPET, 1), encoding='utf-8')


def manifest_path(app, profile_name):
    if not re.fullmatch(r'[a-z][a-z0-9_-]*', profile_name):
        raise ValueError('Invalid build profile name')
    return Path(app) / 'build/blueprint' / f'{profile_name}.json'


def build_target(app, root, sdk, profile_name, profile, run):
    app, root = Path(app), Path(root)
    profile = validate_profile(profile)
    target = profile['platform']
    host_targets = {'darwin': {'ios', 'macos'}, 'win32': {'windows'}, 'linux': {'linux'}}.get(sys.platform, set()) | {'web', 'android'}
    identity = source_identity(root)
    spec = (app / 'pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*([^\s+]+)(?:\+([^\s]+))?', spec, re.M)
    version, number = (match[1], match[2] or '0') if match else ('0.1.0', '0')
    manifest = {'schema': 1, 'source': identity, 'profile': profile, 'configurationSha256': digest(profile),
                'workspaceConfigurationSha256': (read_metadata(root) or {}).get('configurationSha256'),
                'sdk': json.loads((root / '.fvmrc').read_text()), 'lockSha256': hash_file(root / 'pubspec.lock'),
                'app': app.relative_to(root).as_posix(), 'version': version, 'build': number,
                'status': 'NOT_RUN', 'runtime': 'NOT_RUN', 'artifacts': []}
    output = manifest_path(app, profile_name)
    output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    save()
    if target not in host_targets:
        manifest['reason'] = f'{target} requires its matching build host; current host is {sys.platform}'
        save()
        raise ValueError(manifest['reason'])
    if not (app / target).is_dir():
        manifest['reason'] = f'Missing {target} runner in target App'
        save()
        raise ValueError(manifest['reason'])
    if target == 'windows':
        machine = os.environ.get('PROCESSOR_ARCHITEW6432') or os.environ.get('PROCESSOR_ARCHITECTURE') or host_platform.machine()
        host_arch = 'arm64' if machine.lower() in ('arm64', 'aarch64') else 'x64'
        if profile['arch'] != host_arch:
            manifest['reason'] = 'Pinned Flutter builds Windows for its host architecture; use a matching runner'
            save()
            raise ValueError(manifest['reason'])
    command = [sdk.flutter, 'build', 'apk' if target == 'android' else target, '--' + profile['mode'], '--no-pub']
    if target == 'ios' and not profile['codesign']:
        command.append('--no-codesign')
    if target == 'android':
        command += ['--target-platform', {'arm64-v8a': 'android-arm64', 'armeabi-v7a': 'android-arm', 'x86_64': 'android-x64'}[profile['arch']],
                    '--android-project-arg', f'koiAbi={profile["arch"]}']
    if target == 'linux':
        command += ['--target-platform', f'{target}-{profile["arch"]}']
    try:
        manifest['phase'] = 'preparation'
        manifest['preparation'] = {'status': 'RUNNING', 'sourceBefore': identity,
                                   'lockBeforeSha256': manifest['lockSha256'], 'changedInputs': {}}
        manifest['preBuildCommands'] = []
        def prepare(command):
            manifest['preBuildCommands'].append([str(part) for part in command])
            save()
            run(command, app)
        before = source_manifest(root)
        prepare([sdk.flutter, 'pub', 'get', '--enforce-lockfile'])
        if hash_file(root / 'pubspec.lock') != manifest['lockSha256']:
            raise ValueError('Strict pre-build dependency refresh changed the lockfile')
        if source_manifest(root)['source_sha256'] != before['source_sha256']:
            raise ValueError('Source changed during dependency refresh; retry with stable inputs')
        if target in ('android', 'macos', 'ios'):
            # Complete SDK project migrations and native configuration before
            # freezing the real inputs used by compilation.
            preparation_command = [*command, '--config-only']
            if target == 'android':
                # Flutter 3.47 skips mode-aware plugin registration with
                # --no-pub. A plain pub get includes dev plugins, while Gradle
                # excludes them from release: regenerate through the SDK's
                # config-only command, then keep the actual build --no-pub.
                preparation_command.remove('--no-pub')
                preparation_command.append('--pub')
            prepare(preparation_command)
            if target == 'android':
                # Flutter create leaves plugin ABIs in the APK. Apply the filter
                # after config-only so an SDK migration cannot drop it, then freeze.
                ensure_android_abi_filter(app)
            after = source_manifest(root)
            changed = {name: {'beforeSha256': before['files'].get(name), 'afterSha256': after['files'].get(name)}
                       for name in sorted(before['files'].keys() | after['files'].keys())
                       if before['files'].get(name) != after['files'].get(name)}
            manifest['preparation']['changedInputs'] = changed
            native_prefix = (app / target).relative_to(root).as_posix() + '/'
            if any(not name.startswith(native_prefix) for name in changed):
                raise ValueError('Non-native source changed during native dependency preparation')
            if hash_file(root / 'pubspec.lock') != manifest['lockSha256']:
                raise ValueError('Lockfile changed during native dependency preparation')
            identity = source_identity(root)
            manifest['source'] = identity
        manifest['preparation'].update(status='PASS', sourceAfter=identity, lockAfterSha256=manifest['lockSha256'])
        for key, value in {'BUILD_SOURCE': identity['sourceSha256'], 'BUILD_CHANNEL': profile['channel'],
                            'BUILD_PLATFORM': target, 'BUILD_ARCH': profile['arch'], 'BUILD_VERSION': version, 'BUILD_NUMBER': number}.items():
            command.append(f'--dart-define={key}={value}')
        if re.search(r'^name: koi_admin_app$', spec, re.M):
            command.append('--dart-define=ENV=prod')
        manifest['command'] = [str(part) for part in command]
        manifest['phase'] = 'build'
        save()
        run(command, app)
        if source_identity(root)['sourceSha256'] != identity['sourceSha256'] or hash_file(root / 'pubspec.lock') != manifest['lockSha256']:
            raise ValueError('Source or lockfile changed during build; rebuild the final inputs')
        artifact = artifact_path(app, profile)
        if target == 'macos':
            manifest['postBuildCommands'] = []
            def record_run(command, cwd):
                manifest['postBuildCommands'].append([str(part) for part in command])
                run(command, cwd)
            constrain_macos_architecture(artifact, profile, record_run, app)
        manifest['actualArchitectures'] = verify_architecture(artifact, target, profile['arch'])
        manifest['artifacts'] = [describe_artifact(artifact, root)]
        if source_identity(root)['sourceSha256'] != identity['sourceSha256'] or hash_file(root / 'pubspec.lock') != manifest['lockSha256']:
            raise ValueError('Source or lockfile changed during artifact verification')
        manifest['status'] = 'PASS'
    except Exception as error:
        if manifest.get('preparation', {}).get('status') == 'RUNNING':
            manifest['preparation']['status'] = 'FAIL'
        manifest['status'] = 'FAIL'
        manifest['reason'] = str(error)
        raise
    finally:
        save()
    return manifest


def package_target(app, root, profile_name, run):
    app, root = Path(app), Path(root)
    manifest = json.loads(manifest_path(app, profile_name).read_text())
    if manifest.get('status') != 'PASS' or manifest['source']['sourceSha256'] != source_identity(root)['sourceSha256'] or manifest['lockSha256'] != hash_file(root / 'pubspec.lock'):
        raise ValueError('Packaging requires a successful build matching current source and lockfile')
    metadata = read_metadata(root)
    if (metadata or {}).get('configurationSha256') != manifest.get('workspaceConfigurationSha256'):
        raise ValueError('Workspace configuration changed since the successful build')
    configured = (metadata or {}).get('configuration', {}).get('buildProfiles', {}).get(profile_name)
    if configured is not None and digest(validate_profile(configured)) != manifest['configurationSha256']:
        raise ValueError('Build profile changed since the successful build')
    for artifact in manifest['artifacts']:
        path = safe_artifact(root, artifact['path'])
        if describe_artifact(path, root) != artifact:
            raise ValueError('Build artifact changed after verification')
    source = safe_artifact(root, manifest['artifacts'][0]['path'])
    profile = validate_profile(manifest['profile'])
    if digest(profile) != manifest['configurationSha256'] or manifest.get('app') != app.relative_to(root).as_posix():
        raise ValueError('Build manifest profile or app identity is inconsistent')
    actual = verify_architecture(source, profile['platform'], profile['arch'])
    if actual != manifest.get('actualArchitectures'):
        raise ValueError('Build manifest architecture evidence is inconsistent')
    target = profile['platform']
    from tool.blueprint_environment import DEFAULT_FORMATS
    format_name = profile.get('format', DEFAULT_FORMATS[target])
    output = app / 'build/packages' / profile_name
    if output.exists():
        raise ValueError(f'Package output already exists; choose a fresh profile/output: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.package-', dir=output.parent))
    try:
        stem = f'{app.name}-{manifest["version"]}-{profile["channel"]}-{profile["arch"]}'
        packagers = {}
        commands = []
        def package_run(command, cwd):
            commands.append([str(part) for part in command])
            return run(command, cwd)
        if format_name == 'zip':
            shutil.make_archive(str(stage / stem), 'zip', source)
        elif format_name == 'apk':
            shutil.copy2(source, stage / (stem + '.apk'))
        elif format_name == 'app':
            if not profile['codesign']:
                raise ValueError('iOS installation package requires a signed device build; unsigned build remains separate evidence')
            shutil.copytree(source, stage / source.name, symlinks=True)
        elif format_name == 'dmg':
            if sys.platform != 'darwin':
                raise ValueError('DMG packaging requires macOS')
            from tool.blueprint_environment import require_packaging_tools
            packagers = require_packaging_tools('dmg')
            package_run([packagers['hdiutil']['executable'], 'create', '-volname', app.name, '-srcfolder', source, '-ov', '-format', 'UDZO', stage / (stem + '.dmg')], root)
        elif format_name in ('exe', 'deb', 'AppImage'):
            from tool.blueprint_packagers import package_native
            packagers = package_native(format_name, source, stage, app, manifest, stem, package_run)
        else:
            raise ValueError(f'Unsupported package format: {format_name}')
        validate_package_output(stage, source, stem, format_name, profile)
        if format_name == 'dmg':
            package_run([packagers['hdiutil']['executable'], 'verify', stage / (stem + '.dmg')], root)
        # Copy/archive tools read over time. Recheck their complete inputs before
        # promoting the staged output, so concurrent edits cannot earn PASS.
        if source_identity(root)['sourceSha256'] != manifest['source']['sourceSha256'] or hash_file(root / 'pubspec.lock') != manifest['lockSha256']:
            raise ValueError('Source or lockfile changed during packaging')
        for artifact in manifest['artifacts']:
            if describe_artifact(safe_artifact(root, artifact['path']), root) != artifact:
                raise ValueError('Build artifact changed during packaging')
        artifacts = [describe_artifact(file, stage) for file in sorted(stage.iterdir())]
        if not artifacts:
            raise ValueError('Packager produced no artifact')
        (stage / 'package-manifest.json').write_text(json.dumps({'schema': 1, 'build': manifest, 'format': format_name,
            'status': 'PASS', 'installation': 'NOT_RUN', 'tools': packagers, 'commands': commands, 'artifacts': artifacts}, indent=2) + '\n')
        stage.rename(output)
        return output
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def validate_package_output(stage, source, stem, format_name, profile):
    """Validate deliverables, independently of a packager's successful exit code."""
    stage, source = Path(stage), Path(source)
    name = source.name if format_name == 'app' else stem + '.' + format_name
    outputs = list(stage.iterdir())
    if len(outputs) != 1 or outputs[0].name != name or outputs[0].is_symlink():
        raise ValueError('Packager output must contain exactly the expected deliverable')
    output = outputs[0]
    if format_name == 'app':
        if not output.is_dir() or describe_artifact(output, stage)['files'] != describe_artifact(source, source.parent)['files']:
            raise ValueError('Packaged App bundle differs from the verified build')
        return
    if not output.is_file() or output.stat().st_size == 0:
        raise ValueError('Packager produced an empty or missing deliverable')
    if format_name == 'zip':
        expected = {path.relative_to(source).as_posix(): path for path in source.rglob('*') if path.is_file()}
        try:
            with zipfile.ZipFile(output) as archive:
                members = [entry for entry in archive.infolist() if not entry.is_dir()]
                if len(members) != len(expected) or {entry.filename for entry in members} != set(expected):
                    raise ValueError('Packaged ZIP entries differ from the verified build')
                for entry in members:
                    original = expected[entry.filename]
                    if entry.file_size != original.stat().st_size:
                        raise ValueError('Packaged ZIP file size differs from the verified build')
                    hasher = hashlib.sha256()
                    with archive.open(entry) as stream:
                        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                            hasher.update(chunk)
                    if hasher.hexdigest() != hash_file(original):
                        raise ValueError('Packaged ZIP bytes differ from the verified build')
        except (zipfile.BadZipFile, RuntimeError) as error:
            raise ValueError(f'Invalid packaged ZIP: {error}') from error
    elif format_name == 'apk':
        if hash_file(output) != hash_file(source):
            raise ValueError('Packaged APK differs from the verified build')
    elif format_name == 'dmg':
        with output.open('rb') as stream:
            if output.stat().st_size < 512:
                raise ValueError('Packager produced a truncated DMG')
            stream.seek(-512, os.SEEK_END)
            if stream.read(4) != b'koly':
                raise ValueError('Packager produced an invalid UDIF DMG')
    elif format_name == 'exe':
        with output.open('rb') as stream:
            if stream.read(2) != b'MZ' or not binary_architectures(output):
                raise ValueError('Packager produced an invalid PE installer')
    elif format_name == 'AppImage':
        with output.open('rb') as stream:
            header = stream.read(11)
        if header[:4] != b'\x7fELF' or header[8:11] != b'AI\x02':
            raise ValueError('Packager produced an invalid type-2 AppImage')
        verify_architecture(output, 'linux', profile['arch'])
    elif format_name == 'deb':
        validate_debian_archive(output)
    else:
        raise ValueError('Unsupported package format')


def validate_debian_archive(path):
    """Check the Debian ar envelope without extracting files or trusting suffixes."""
    members = []
    with Path(path).open('rb') as stream:
        if stream.read(8) != b'!<arch>\n':
            raise ValueError('Packager produced an invalid Debian archive')
        total = Path(path).stat().st_size
        while stream.tell() < total:
            header = stream.read(60)
            if len(header) != 60 or header[58:60] != b'`\n':
                raise ValueError('Debian archive member header is truncated or invalid')
            try:
                name = header[:16].decode('ascii').strip().rstrip('/')
                size = int(header[48:58].strip())
            except (UnicodeDecodeError, ValueError) as error:
                raise ValueError('Invalid Debian archive member') from error
            if size <= 0 or stream.tell() + size + size % 2 > total:
                raise ValueError('Debian archive member exceeds its container')
            if not members and (name != 'debian-binary' or size != 4 or stream.read(4) != b'2.0\n'):
                raise ValueError('Debian archive is missing format version 2.0')
            else:
                if members:
                    stream.seek(size, os.SEEK_CUR)
                stream.seek(size % 2, os.SEEK_CUR)
            members.append(name)
        if len(members) != 3 or not re.fullmatch(r'control\.tar(?:\.(?:gz|xz|zst|bz2|lzma))?', members[1]) or not re.fullmatch(r'data\.tar(?:\.(?:gz|xz|zst|bz2|lzma))?', members[2]):
            raise ValueError('Debian archive must contain control and payload members')


def safe_artifact(root, relative):
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts or not (root / path).resolve().is_relative_to(root.resolve()):
        raise ValueError('Invalid artifact path')
    return root / path


def constrain_macos_architecture(artifact, profile, run, cwd):
    """Local unsigned builds are thinned before hashing; never silently break signing."""
    arch = profile['arch']
    universal = []
    for file in artifact.rglob('*'):
        if not file.is_file() or file.is_symlink():
            continue
        actual = binary_architectures(file)
        if len(actual) > 1:
            if arch not in actual:
                raise ValueError(f'Universal binary lacks selected architecture: {file}')
            universal.append(file)
    if not universal:
        return
    if profile['codesign']:
        raise ValueError('Signed macOS build contains multiple architectures; configure Xcode ARCHS for the selected profile before building')
    lipo, codesign = shutil.which('lipo'), shutil.which('codesign')
    if not lipo or not codesign:
        raise ValueError('Single-architecture macOS output requires lipo and codesign')
    for file in universal:
        temporary = file.with_name(file.name + '.blueprint-thin')
        try:
            run([lipo, file, '-thin', arch, '-output', temporary], cwd)
            if set(binary_architectures(temporary)) != {arch}:
                raise ValueError('lipo output architecture could not be verified')
            temporary.chmod(file.stat().st_mode)
            temporary.replace(file)
        finally:
            temporary.unlink(missing_ok=True)
    run([codesign, '--force', '--deep', '--sign', '-', '--preserve-metadata=entitlements,requirements,flags,runtime', artifact], cwd)
    run([codesign, '--verify', '--deep', '--strict', artifact], cwd)
