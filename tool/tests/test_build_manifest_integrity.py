import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tool.blueprint_build import build_target, package_target, verify_architecture, binary_architectures, constrain_macos_architecture, validate_package_output, validate_debian_archive
from tool.blueprint_provenance import source_identity


class BuildManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'apps/demo_app'
        (self.app / 'web').mkdir(parents=True)
        (self.app / 'pubspec.yaml').write_text('name: demo_app\nversion: 1.0.0+2\n')
        (self.root / '.fvmrc').write_text('{"flutter":"3.47.2"}')
        (self.root / 'pubspec.lock').write_text('lock')
        self.identity = {'sourceSha256': 'source', 'commit': None, 'dirty': False}
        self.sdk = SimpleNamespace(flutter='flutter')

    def run_build(self, command, cwd):
        bundle = self.app / 'build/web'
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / 'index.html').write_text('index')
        (bundle / 'flutter_bootstrap.js').write_text('bootstrap')

    def build(self):
        with patch('tool.blueprint_build.source_identity', return_value=self.identity):
            return build_target(self.app, self.root, self.sdk, 'web', {'platform': 'web'}, self.run_build)

    def test_web_package_requires_same_inputs_and_records_installation_not_run(self):
        self.build()
        with patch('tool.blueprint_build.source_identity', return_value=self.identity):
            path = package_target(self.app, self.root, 'web', lambda c, d: None)
            manifest = json.loads((path / 'package-manifest.json').read_text())
            self.assertEqual(manifest['installation'], 'NOT_RUN')
            self.assertEqual(manifest['status'], 'PASS')
            self.assertEqual(manifest['build']['runtime'], 'NOT_RUN')
            self.assertTrue(manifest['artifacts'][0]['sha256'])
            with self.assertRaisesRegex(ValueError, 'already exists'):
                package_target(self.app, self.root, 'web', lambda c, d: None)

    def test_edited_artifact_or_manifest_cannot_package(self):
        self.build()
        target = self.app / 'build/web/index.html'
        target.write_text('changed')
        with patch('tool.blueprint_build.source_identity', return_value=self.identity):
            with self.assertRaisesRegex(ValueError, 'artifact changed'):
                package_target(self.app, self.root, 'web', lambda c, d: None)
        self.build()
        path = self.app / 'build/blueprint/web.json'
        manifest = json.loads(path.read_text())
        manifest['profile']['channel'] = 'other'
        path.write_text(json.dumps(manifest))
        with patch('tool.blueprint_build.source_identity', return_value=self.identity):
            with self.assertRaisesRegex(ValueError, 'inconsistent'):
                package_target(self.app, self.root, 'web', lambda c, d: None)

    def test_source_change_during_build_fails_and_wrong_host_is_not_run(self):
        with patch('tool.blueprint_build.source_identity', side_effect=[self.identity, {**self.identity, 'sourceSha256': 'changed'}]):
            with self.assertRaisesRegex(ValueError, 'Source or lockfile changed'):
                build_target(self.app, self.root, self.sdk, 'web', {'platform': 'web'}, self.run_build)
        self.assertEqual(json.loads((self.app / 'build/blueprint/web.json').read_text())['status'], 'FAIL')
        with patch('tool.blueprint_build.source_identity', return_value=self.identity), patch('tool.blueprint_build.sys.platform', 'darwin'):
            with self.assertRaisesRegex(ValueError, 'matching build host'):
                build_target(self.app, self.root, self.sdk, 'win', {'platform': 'windows'}, self.run_build)
        self.assertEqual(json.loads((self.app / 'build/blueprint/win.json').read_text())['status'], 'NOT_RUN')

    def native_fixture(self, target='macos'):
        native = self.app / target
        native.mkdir()
        (native / 'Runner.xcodeproj').mkdir()
        (native / 'Runner.xcworkspace').mkdir()
        (native / 'Runner.xcodeproj/project.pbxproj').write_text('before integration')
        (native / 'Runner.xcworkspace/contents.xcworkspacedata').write_text('before integration')
        product = 'macos/Build/Products/Release' if target == 'macos' else 'ios/iphoneos'
        binary = self.app / 'build' / product / 'Demo.app/Contents/MacOS/Demo'
        calls = []
        def runner(command, cwd):
            calls.append([str(part) for part in command])
            if '--config-only' in command:
                (native / 'Podfile.lock').write_text('resolved pods')
                (native / 'Runner.xcodeproj/project.pbxproj').write_text('integrated project')
                (native / 'Runner.xcworkspace/contents.xcworkspacedata').write_text('integrated workspace')
            elif 'build' in command:
                binary.parent.mkdir(parents=True, exist_ok=True)
                binary.write_bytes(b'\xcf\xfa\xed\xfe' + struct.pack('<I', 0x0100000c))
        return native, calls, runner

    def test_first_apple_build_prepares_native_inputs_before_freezing_identity(self):
        native, calls, runner = self.native_fixture()
        before = source_identity(self.root)
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            manifest = build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, runner)
        self.assertEqual(manifest['status'], 'PASS')
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0][1:], ['pub', 'get', '--enforce-lockfile'])
        self.assertIn('--config-only', calls[1])
        self.assertNotIn('--config-only', calls[2])
        self.assertEqual(manifest['preBuildCommands'], calls[:2])
        self.assertEqual(manifest['preparation']['sourceBefore'], before)
        self.assertEqual(manifest['source'], source_identity(self.root))
        self.assertNotEqual(manifest['source']['sourceSha256'], before['sourceSha256'])
        self.assertIn('--dart-define=BUILD_SOURCE=' + manifest['source']['sourceSha256'], calls[2])
        changed = manifest['preparation']['changedInputs']
        self.assertEqual(set(changed), {str(path.relative_to(self.root)) for path in (
            native / 'Podfile.lock', native / 'Runner.xcodeproj/project.pbxproj', native / 'Runner.xcworkspace/contents.xcworkspacedata')})
        self.assertIsNone(changed[str((native / 'Podfile.lock').relative_to(self.root))]['beforeSha256'])
        # Once prepared, repeating the same command freezes exactly the same inputs.
        calls.clear()
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            again = build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, runner)
        self.assertEqual(again['source'], manifest['source'])
        self.assertEqual(again['preparation']['changedInputs'], {})

    def test_native_input_edit_after_preparation_fails_and_keeps_failed_manifest(self):
        native, calls, runner = self.native_fixture()
        def concurrent_edit(command, cwd):
            runner(command, cwd)
            if 'build' in command and '--config-only' not in command:
                (native / 'Runner.xcodeproj/project.pbxproj').write_text('concurrent edit after freeze')
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            with self.assertRaisesRegex(ValueError, 'Source or lockfile changed during build'):
                build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, concurrent_edit)
        manifest = json.loads((self.app / 'build/blueprint/mac.json').read_text())
        self.assertEqual(manifest['status'], 'FAIL')
        self.assertEqual(manifest['phase'], 'build')
        self.assertEqual(manifest['preparation']['status'], 'PASS')
        self.assertNotEqual(manifest['source']['sourceSha256'], source_identity(self.root)['sourceSha256'])

    def test_native_preparation_failure_and_unrelated_edits_never_start_build(self):
        native, calls, runner = self.native_fixture()
        def unrelated_edit(command, cwd):
            runner(command, cwd)
            if '--config-only' in command:
                (self.app / 'pubspec.yaml').write_text('name: concurrent_edit\n')
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            with self.assertRaisesRegex(ValueError, 'Non-native source changed'):
                build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, unrelated_edit)
        manifest = json.loads((self.app / 'build/blueprint/mac.json').read_text())
        self.assertEqual(manifest['preparation']['status'], 'FAIL')
        self.assertEqual(len(calls), 2)
        self.assertNotIn('command', manifest)
        def failing_prepare(command, cwd):
            if '--config-only' in command:
                raise RuntimeError('pod install failed')
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            with self.assertRaisesRegex(RuntimeError, 'pod install failed'):
                build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, failing_prepare)
        manifest = json.loads((self.app / 'build/blueprint/mac.json').read_text())
        self.assertEqual(manifest['status'], 'FAIL')
        self.assertEqual(manifest['preparation']['status'], 'FAIL')
        self.assertIn('--config-only', manifest['preBuildCommands'][-1])

    def test_ios_preparation_preserves_unsigned_mode_and_wrong_host_never_prepares(self):
        native, calls, runner = self.native_fixture('ios')
        with patch('tool.blueprint_build.sys.platform', 'darwin'):
            manifest = build_target(self.app, self.root, self.sdk, 'ios', {'platform': 'ios', 'codesign': False}, runner)
        self.assertEqual(manifest['status'], 'PASS')
        self.assertIn('--no-codesign', calls[1])
        self.assertIn('--no-codesign', calls[2])
        calls.clear()
        with patch('tool.blueprint_build.sys.platform', 'linux'):
            with self.assertRaisesRegex(ValueError, 'matching build host'):
                build_target(self.app, self.root, self.sdk, 'ios', {'platform': 'ios'}, runner)
        manifest = json.loads((self.app / 'build/blueprint/ios.json').read_text())
        self.assertEqual(manifest['status'], 'NOT_RUN')
        self.assertEqual(calls, [])

    def test_packaging_rechecks_inputs_before_promoting_staged_output(self):
        import shutil
        self.build()
        original = shutil.make_archive
        def archive_then_edit(*args, **kwargs):
            result = original(*args, **kwargs)
            (self.app / 'build/web/index.html').write_text('changed during archive')
            return result
        with patch('tool.blueprint_build.source_identity', return_value=self.identity), patch('tool.blueprint_build.shutil.make_archive', side_effect=archive_then_edit):
            with self.assertRaisesRegex(ValueError, 'ZIP file size differs|artifact changed during packaging'):
                package_target(self.app, self.root, 'web', lambda c, d: None)
        self.assertFalse((self.app / 'build/packages/web').exists())
        self.assertEqual(list((self.app / 'build/packages').iterdir()), [])
        self.build()
        with patch('tool.blueprint_build.source_identity', side_effect=[self.identity, {**self.identity, 'sourceSha256': 'changed'}]):
            with self.assertRaisesRegex(ValueError, 'Source or lockfile changed during packaging'):
                package_target(self.app, self.root, 'web', lambda c, d: None)
        self.assertFalse((self.app / 'build/packages/web').exists())

    def test_successful_archiver_cannot_publish_missing_changed_or_extra_payload(self):
        import zipfile
        self.build()
        for mode in ('missing', 'changed', 'extra', 'duplicate'):
            def archive(output, format_name, source):
                with zipfile.ZipFile(output + '.zip', 'w') as result:
                    result.writestr('index.html', 'changed' if mode == 'changed' else 'index')
                    if mode != 'missing': result.writestr('flutter_bootstrap.js', 'bootstrap')
                    if mode == 'extra': result.writestr('unexpected.txt', 'extra')
                    if mode == 'duplicate': result.writestr('index.html', 'index')
            with self.subTest(mode=mode), patch('tool.blueprint_build.source_identity', return_value=self.identity), patch('tool.blueprint_build.shutil.make_archive', side_effect=archive):
                with self.assertRaisesRegex(ValueError, 'ZIP'):
                    package_target(self.app, self.root, 'web', lambda c, d: None)
            self.assertFalse((self.app / 'build/packages/web').exists())
            self.assertEqual(list((self.app / 'build/packages').iterdir()), [])

    def test_deliverable_validation_rejects_extra_output_truncated_dmg_and_invalid_pe(self):
        stage = self.root / 'package'
        stage.mkdir()
        artifact = stage / 'demo.dmg'
        artifact.write_bytes(b'not a disk image')
        with self.assertRaisesRegex(ValueError, 'truncated DMG'):
            validate_package_output(stage, self.app, 'demo', 'dmg', {})
        artifact.write_bytes(b'\0' * 1024)
        with self.assertRaisesRegex(ValueError, 'invalid UDIF'):
            validate_package_output(stage, self.app, 'demo', 'dmg', {})
        artifact.write_bytes(b'payload' + b'koly' + b'\0' * 508)
        validate_package_output(stage, self.app, 'demo', 'dmg', {})
        (stage / 'unexpected').write_text('unowned file')
        with self.assertRaisesRegex(ValueError, 'exactly'):
            validate_package_output(stage, self.app, 'demo', 'dmg', {})
        (stage / 'unexpected').unlink()
        artifact.unlink()
        (stage / 'demo.exe').write_bytes(b'MZonly')
        with self.assertRaisesRegex(ValueError, 'PE'):
            validate_package_output(stage, self.app, 'demo', 'exe', {})

    def test_debian_envelope_requires_version_control_payload_and_complete_lengths(self):
        archive = self.root / 'package.deb'
        def member(name, content):
            header = f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(content):<10}`\n'.encode('ascii')
            return header + content + (b'\n' if len(content) % 2 else b'')
        valid = b'!<arch>\n' + member('debian-binary', b'2.0\n') + member('control.tar.xz', b'control') + member('data.tar.xz', b'payload')
        archive.write_bytes(valid)
        validate_debian_archive(archive)
        for broken in (valid[:-1], b'!<arch>\n', valid.replace(b'data.tar.xz', b'other.file ')):
            archive.write_bytes(broken)
            with self.assertRaises(ValueError): validate_debian_archive(archive)

    def test_dmg_validation_command_is_required_and_recorded(self):
        (self.app / 'macos').mkdir()
        binary = self.app / 'build/macos/Build/Products/Release/Demo.app/Contents/MacOS/Demo'
        def build_runner(command, cwd):
            if command[1:2] == ['build']:
                binary.parent.mkdir(parents=True, exist_ok=True)
                binary.write_bytes(b'\xcf\xfa\xed\xfe' + struct.pack('<I', 0x0100000c))
        calls = []
        def packager(command, cwd):
            calls.append([str(part) for part in command])
            if command[1] == 'create':
                Path(command[-1]).write_bytes(b'payload' + b'koly' + b'\0' * 508)
        with patch('tool.blueprint_build.source_identity', return_value=self.identity), patch('tool.blueprint_build.sys.platform', 'darwin'), patch('tool.blueprint_environment.require_packaging_tools', return_value={'hdiutil': {'executable': 'hdiutil'}}):
            build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos'}, build_runner)
            output = package_target(self.app, self.root, 'mac', packager)
        self.assertEqual([command[1] for command in calls], ['create', 'verify'])
        self.assertEqual(json.loads((output / 'package-manifest.json').read_text())['commands'], calls)
    def test_fat_or_truncated_binary_cannot_pass_single_arch_profile(self):
        file = self.root / 'fat'
        data = bytearray(48)
        data[:4] = b'\xca\xfe\xba\xbe'
        struct.pack_into('>I', data, 4, 2)
        struct.pack_into('>I', data, 8, 0x0100000c)
        struct.pack_into('>I', data, 28, 0x01000007)
        file.write_bytes(data)
        with self.assertRaises(ValueError): verify_architecture(file, 'macos', 'arm64')
        for broken in (b'MZ', b'\x7fELF', b'\xca\xfe\xba\xbe'):
            file.write_bytes(broken)
            with self.assertRaises(ValueError): binary_architectures(file)

    def test_apk_directory_names_cannot_falsify_actual_architecture(self):
        import zipfile
        archive = self.root / 'app.apk'
        header = bytearray(64)
        header[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', header, 18, 62)
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('lib/arm64-v8a/libflutter.so', header)
        with self.assertRaisesRegex(ValueError, 'contradicts'):
            verify_architecture(archive, 'android', 'arm64-v8a')
        struct.pack_into('<H', header, 18, 183)
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('lib/arm64-v8a/libflutter.so', header)
        self.assertEqual(verify_architecture(archive, 'android', 'arm64-v8a'), ['arm64-v8a'])

    def test_unsigned_macos_thinning_and_signing_commands_are_recorded(self):
        (self.app / 'macos').mkdir()
        binary = self.app / 'build/macos/Build/Products/Release/Demo.app/Contents/MacOS/Demo'
        fat = bytearray(48)
        fat[:4] = b'\xca\xfe\xba\xbe'
        struct.pack_into('>I', fat, 4, 2)
        struct.pack_into('>I', fat, 8, 0x0100000c)
        struct.pack_into('>I', fat, 28, 0x01000007)
        thin = b'\xcf\xfa\xed\xfe' + struct.pack('<I', 0x0100000c)
        def runner(command, cwd):
            if 'build' in command:
                binary.parent.mkdir(parents=True, exist_ok=True)
                binary.write_bytes(fat)
            if command[0] == '/tools/lipo': Path(command[-1]).write_bytes(thin)
        with patch('tool.blueprint_build.source_identity', return_value=self.identity), patch('tool.blueprint_build.sys.platform', 'darwin'), patch('tool.blueprint_build.shutil.which', side_effect=lambda name: '/tools/' + name):
            manifest = build_target(self.app, self.root, self.sdk, 'mac', {'platform': 'macos', 'arch': 'arm64'}, runner)
        self.assertEqual(manifest['status'], 'PASS')
        self.assertEqual(manifest['actualArchitectures'], ['arm64'])
        commands = manifest['postBuildCommands']
        self.assertEqual([command[0] for command in commands], ['/tools/lipo', '/tools/codesign', '/tools/codesign'])
        self.assertIn('--preserve-metadata=entitlements,requirements,flags,runtime', commands[1])
        self.assertIn('--verify', commands[2])
        self.assertEqual(binary.read_bytes(), thin)

    def test_signed_universal_macos_is_never_silently_resigned(self):
        bundle = self.root / 'App.app'
        bundle.mkdir()
        file = bundle / 'runner'
        data = bytearray(48)
        data[:4] = b'\xca\xfe\xba\xbe'
        struct.pack_into('>I', data, 4, 2)
        struct.pack_into('>I', data, 8, 0x0100000c)
        struct.pack_into('>I', data, 28, 0x01000007)
        file.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'Signed macOS'):
            constrain_macos_architecture(bundle, {'arch': 'arm64', 'codesign': True}, lambda c, d: self.fail('must not run'), self.root)
        self.assertEqual(file.read_bytes(), data)


if __name__ == '__main__':
    unittest.main()
