import json
import hashlib
import io
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tool.blueprint_assets import asset_plan, generate_assets
from tool.blueprint_branding import apply_brand
from tool.blueprint_environment import inspect_tool, doctor_report, inspect_appimage_runtime
from tool.blueprint_packagers import package_native


class AssetPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / 'demo_app'
        self.app.mkdir()

    def write(self, path, value):
        target = self.app / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(value if isinstance(value, bytes) else value.encode())
        return target

    def test_assets_deterministic_case_collision_and_dirty_protection(self):
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n  assets:\n    - assets/\n')
        self.write('assets/photo.png', b'bytes')
        self.write('assets/deeper/not_implicitly_declared.png', b'nested')
        first = generate_assets(self.app)
        self.assertEqual(first['assets'], ['assets/photo.png'])
        self.assertEqual(generate_assets(self.app)['changed'], [])
        output = self.app / 'lib/shared/assets/app_assets.dart'
        output.write_text('// user edit')
        self.write('assets/next.png', b'next')
        with self.assertRaisesRegex(ValueError, 'local edit'):
            generate_assets(self.app)
        self.assertEqual(output.read_text(), '// user edit')
        self.write('assets/photo-one.png', b'case')
        self.write('assets/photo_one.png', b'case')
        with self.assertRaisesRegex(ValueError, 'collision'):
            asset_plan(self.app)

    def test_missing_and_escaping_assets_fail_before_writes(self):
        self.write('pubspec.yaml', 'flutter:\n  assets:\n    - assets/missing.png\n')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            generate_assets(self.app)
        self.write('pubspec.yaml', 'flutter:\n  assets:\n    - ../outside.png\n')
        with self.assertRaises(ValueError):
            generate_assets(self.app)
        self.assertFalse((self.app / 'lib').exists())

    def test_typed_asset_consumer_is_owned_and_conflicts_roll_back_all_outputs(self):
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n  assets:\n    - assets/\n')
        self.write('assets/readme.txt', 'user asset')
        user_test = self.write('test/typed_assets_test.dart', '// existing test\n')
        with self.assertRaisesRegex(ValueError, 'local edit'):
            generate_assets(self.app)
        self.assertFalse((self.app / 'lib/shared/assets/app_assets.dart').exists())
        self.assertFalse((self.app / '.blueprint/assets.json').exists())
        self.assertEqual(user_test.read_text(), '// existing test\n')
        user_test.unlink()
        generate_assets(self.app)
        receipt = json.loads((self.app / '.blueprint/assets.json').read_text())
        self.assertIn('test/typed_assets_test.dart', receipt['outputs'])
        original_constants = (self.app / 'lib/shared/assets/generated/app_assets.dart').read_bytes()
        user_test.write_text('// edited consumer\n')
        (self.app / 'assets/readme.txt').rename(self.app / 'assets/renamed.txt')
        with self.assertRaisesRegex(ValueError, 'local edit'):
            generate_assets(self.app)
        self.assertEqual((self.app / 'lib/shared/assets/generated/app_assets.dart').read_bytes(), original_constants)
        self.assertEqual(json.loads((self.app / '.blueprint/assets.json').read_text()), receipt)

    def test_asset_and_package_rename_refresh_consumer_and_measured_lengths(self):
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n  assets:\n    - assets/\n')
        asset = self.write('assets/first.txt', '中文')
        self.write('assets/empty.txt', b'')
        generate_assets(self.app)
        constants = (self.app / 'lib/shared/assets/generated/app_assets.dart').read_text()
        self.assertIn('assetsFirstTxt: 6,', constants)
        self.assertIn('assetsEmptyTxt: 0,', constants)
        consumer = self.app / 'test/typed_assets_test.dart'
        self.assertIn('package:demo_app/shared/assets/app_assets.dart', consumer.read_text())
        asset.rename(self.app / 'assets/renamed.txt')
        self.write('pubspec.yaml', 'name: renamed_app\nflutter:\n  assets:\n    - assets/\n')
        generate_assets(self.app)
        constants = (self.app / 'lib/shared/assets/generated/app_assets.dart').read_text()
        self.assertNotIn('assetsFirstTxt', constants)
        self.assertIn('assetsRenamedTxt: 6,', constants)
        self.assertIn('package:renamed_app/shared/assets/app_assets.dart', consumer.read_text())
        self.assertNotIn('package:demo_app/', consumer.read_text())
        self.assertEqual(generate_assets(self.app)['changed'], [])

    def test_no_assets_registers_an_explicit_skip_and_helper_names_do_not_collide(self):
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n')
        result = generate_assets(self.app)
        self.assertEqual(result['assets'], [])
        self.assertIn("skip: 'No assets declared; no bundle loading was verified.'", (self.app / 'test/typed_assets_test.dart').read_text())
        self.assertIn('all = <String>[]', (self.app / 'lib/shared/assets/generated/app_assets.dart').read_text())
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n  assets:\n    - all\n    - bundle_key\n')
        self.write('all', 'a')
        self.write('bundle_key', 'b')
        generate_assets(self.app)
        constants = (self.app / 'lib/shared/assets/generated/app_assets.dart').read_text()
        self.assertIn("assetAll = 'all'", constants)
        self.assertIn("assetBundleKey = 'bundle_key'", constants)
        self.assertEqual(generate_assets(self.app)['changed'], [])

    def test_legacy_asset_receipt_migrates_to_generated_class_without_deleting_entry(self):
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n  assets:\n    - assets/\n')
        self.write('assets/note.txt', 'asset')
        entry = self.write('lib/shared/assets/app_assets.dart', '// legacy owned constants\n')
        original = entry.read_bytes()
        self.write('.blueprint/assets.json', json.dumps({'schema': 1, 'inputs': {}, 'outputs': {
            'lib/shared/assets/app_assets.dart': hashlib.sha256(original).hexdigest(),
        }}))
        entry.write_text('// user edit to legacy constants\n')
        with self.assertRaisesRegex(ValueError, 'local edit'):
            generate_assets(self.app)
        self.assertFalse((self.app / 'lib/shared/assets/generated/app_assets.dart').exists())
        entry.write_bytes(original)
        generate_assets(self.app)
        self.assertIn("export 'generated/app_assets.dart';", entry.read_text())
        generated = self.app / 'lib/shared/assets/generated/app_assets.dart'
        self.assertIn('class AppAssets', generated.read_text())
        self.assertEqual(set(json.loads((self.app / '.blueprint/assets.json').read_text())['outputs']), {
            'lib/shared/assets/app_assets.dart', 'lib/shared/assets/generated/app_assets.dart',
            'test/typed_assets_test.dart',
        })
        self.assertEqual(generate_assets(self.app)['changed'], [])
        generated.write_text('// edited generated implementation\n')
        with self.assertRaisesRegex(ValueError, 'local edit'):
            generate_assets(self.app)

    def test_actual_coverage_percentage_excludes_generated_assets_not_manual_code(self):
        import blueprint
        self.write('pubspec.yaml', 'name: demo_app\nflutter:\n')
        generate_assets(self.app)
        self.write('lib/manual.dart', 'int value() => 1;\n')
        report = self.write('coverage/lcov.info', 'SF:lib/shared/assets/generated/app_assets.dart\nDA:1,0\nend_of_record\nSF:lib/manual.dart\nDA:1,1\nend_of_record\n')
        sdk = SimpleNamespace(flutter='flutter', dart='dart')
        with patch.object(blueprint, 'run'), patch('sys.stdout', new_callable=io.StringIO) as output:
            blueprint.coverage(self.root, sdk, [self.app], 80)
        self.assertIn('100.00% (1/1)', output.getvalue())
        report.write_text(report.read_text().replace('DA:1,1', 'DA:1,0'))
        with patch.object(blueprint, 'run'), patch('sys.stdout', new_callable=io.StringIO):
            with self.assertRaisesRegex(blueprint.BlueprintError, 'Coverage below threshold'):
                blueprint.coverage(self.root, sdk, [self.app], 80)

    def test_shared_doctor_rejects_wrong_host_old_and_wrong_tools(self):
        tool = self.write('tool.exe', b'executable')
        options = {'which': lambda _: str(tool), 'env': {}, 'host': 'win32'}
        self.assertEqual(inspect_tool('inno', **options, probe=lambda _: 'Inno Setup Compiler 6.3.3')['status'], 'AVAILABLE')
        self.assertEqual(inspect_tool('inno', **options, probe=lambda _: 'Inno Setup Compiler 6.2.0')['status'], 'UNSUPPORTED')
        self.assertEqual(inspect_tool('inno', **options, probe=lambda _: 'Other 7.1.0')['status'], 'UNSUPPORTED')
        self.assertEqual(inspect_tool('dpkg', **options)['status'], 'WRONG_HOST')
        with patch('tool.blueprint_environment.inspect_tool', return_value={'status': 'MISSING'}):
            self.assertEqual(doctor_report(formats=['exe'])['status'], 'INCOMPLETE')

    def test_doctor_derives_default_formats_and_verifies_runtime_bytes_and_architecture(self):
        runtime = self.write('runtime', b'not a runtime')
        env = {'BLUEPRINT_APPIMAGE_RUNTIME': str(runtime)}
        self.assertEqual(inspect_appimage_runtime(host='linux', env=env)['status'], 'UNSUPPORTED')
        self.assertEqual(inspect_appimage_runtime(host='darwin', env=env)['status'], 'WRONG_HOST')
        header = bytearray(64)
        header[:6] = b'\x7fELF\x02\x01'
        header[8:11] = b'AI\x02'
        struct.pack_into('<H', header, 18, 62)
        runtime.write_bytes(header)
        actual = inspect_appimage_runtime('x64', host='linux', env=env)
        self.assertEqual(actual['status'], 'AVAILABLE')
        self.assertEqual(actual['actualArchitecture'], 'x64')
        self.assertTrue(actual['sha256'])
        self.assertEqual(inspect_appimage_runtime('arm64', host='linux', env=env)['status'], 'UNSUPPORTED')
        with patch('tool.blueprint_environment.inspect_tool', side_effect=lambda key: {'tool': key, 'status': 'AVAILABLE'}):
            report = doctor_report(profiles=[{'platform': 'macos'}, {'platform': 'linux'}])
        self.assertEqual([item['tool'] for item in report['tools']], ['hdiutil', 'dpkg', 'shlibdeps'])
        with patch('tool.blueprint_environment.inspect_tool', return_value={'status': 'AVAILABLE'}), patch.dict('os.environ', env), patch('tool.blueprint_environment.sys.platform', 'linux'):
            self.assertEqual(doctor_report(profiles=[{'platform': 'linux', 'arch': 'arm64', 'format': 'AppImage'}])['status'], 'INCOMPLETE')

    def brand_fixture(self):
        self.write('input/icon.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><circle cx="64" cy="64" r="50" fill="#4477cc"/></svg>')
        for platform in ('android', 'windows', 'linux', 'web', 'ios', 'macos'):
            (self.app / platform).mkdir(exist_ok=True)
        for platform in ('ios', 'macos'):
            self.write(platform + '/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json', json.dumps({'images': [{'filename': 'icon.png', 'size': '32x32', 'scale': '2x'}]}))
        return {'iconForeground': 'input/icon.svg', 'iconBackground': '#ffffff'}

    def test_brand_stages_all_formats_and_rejects_edited_output(self):
        brand = self.brand_fixture()
        tool = {'status': 'AVAILABLE', 'executable': 'magick', 'version': '7.1.2'}
        def render(command, cwd):
            Path(command[-1]).write_bytes(('render ' + ' '.join(str(p) for p in command[:-1] if 'blueprint-brand-' not in str(p))).encode())
        with patch('tool.blueprint_branding.inspect_tool', return_value=tool):
            result = apply_brand(self.app, brand, ['android', 'ios', 'macos', 'web', 'windows', 'linux'], run=render)
            self.assertIn('windows/runner/resources/app_icon.ico', result['outputs'])
            self.assertIn('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml', result['outputs'])
            target = self.app / 'web/favicon.png'
            target.write_bytes(b'user edited')
            with self.assertRaisesRegex(ValueError, 'local edit'):
                apply_brand(self.app, brand, ['android', 'ios', 'macos', 'web', 'windows', 'linux'], run=render)
            self.assertEqual(target.read_bytes(), b'user edited')

    def test_failed_brand_renderer_leaves_target_untouched(self):
        brand = self.brand_fixture()
        with patch('tool.blueprint_branding.inspect_tool', return_value={'status': 'AVAILABLE', 'executable': 'magick'}):
            with self.assertRaises(RuntimeError):
                apply_brand(self.app, brand, ['web'], run=lambda c, d: (_ for _ in ()).throw(RuntimeError('renderer failed')))
        self.assertFalse((self.app / 'assets').exists())
        self.assertFalse((self.app / '.blueprint').exists())

    @unittest.skipUnless(shutil.which('magick'), 'ImageMagick not installed on this host')
    def test_real_brand_rasterizer_is_repeatable_and_has_expected_dimensions(self):
        brand = self.brand_fixture()
        apply_brand(self.app, brand, ['web', 'windows'])
        self.assertEqual(apply_brand(self.app, brand, ['web', 'windows'])['changed'], [])
        image = self.app / 'web/icons/Icon-512.png'
        self.assertEqual(image.read_bytes()[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', image.read_bytes()[16:24]), (512, 512))
        self.assertEqual((self.app / 'windows/runner/resources/app_icon.ico').read_bytes()[:4], b'\x00\x00\x01\x00')

    def native_fixture(self, target):
        source = self.app / 'build/bundle'
        source.mkdir(parents=True)
        stage = self.app / 'build/stage'
        stage.mkdir()
        data = bytearray(64)
        if target == 'windows':
            data[:2] = b'MZ'
            name = 'demo_app.exe'
        else:
            data[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', data, 18, 62)
            name = 'demo_app'
        executable = source / name
        executable.write_bytes(data)
        executable.chmod(0o755)
        manifest = {'version': '1.2.3', 'profile': {'arch': 'x64', 'platform': target}}
        return source, stage, manifest

    def test_windows_installer_input_includes_full_bundle_without_autorun(self):
        source, stage, manifest = self.native_fixture('windows')
        commands = []
        def run(command, cwd):
            text = Path(command[-1]).read_text()
            self.assertIn('recursesubdirs', text)
            self.assertIn('PrivilegesRequired=lowest', text)
            self.assertNotIn('[Run]', text)
            self.assertIn('x64compatible', text)
            commands.append(command)
            (stage / 'demo.exe').write_bytes(b'MZinstaller')
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value={'inno': {'executable': 'iscc'}}):
            package_native('exe', source, stage, self.app, manifest, 'demo', run)
        self.assertEqual(len(commands), 1)
        self.assertFalse((stage / '.work').exists())

    def test_deb_computes_dependencies_and_requires_real_archive(self):
        source, stage, manifest = self.native_fixture('linux')
        tools = {'dpkg': {'executable': 'dpkg-deb'}, 'shlibdeps': {'executable': 'dpkg-shlibdeps'}}
        def run(command, cwd):
            control = (Path(command[-2]) / 'DEBIAN/control').read_text()
            self.assertIn('Architecture: amd64', control)
            self.assertIn('Depends: libc6 (>= 2.34)', control)
            self.assertIn('--root-owner-group', command)
            Path(command[-1]).write_bytes(b'!<arch>\narchive')
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value=tools), patch('tool.blueprint_packagers.subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout='shlibs:Depends=libc6 (>= 2.34)\n')):
            package_native('deb', source, stage, self.app, manifest, 'demo', run)
        self.assertFalse((stage / '.work').exists())

    def test_appimage_uses_pinned_runtime_bundles_dependencies_and_checks_magic(self):
        source, stage, manifest = self.native_fixture('linux')
        runtime = self.app / 'runtime'
        content = bytearray((source / 'demo_app').read_bytes())
        content[8:11] = b'AI\x02'
        runtime.write_bytes(content)
        tools = {'linuxdeploy': {'executable': 'linuxdeploy'}, 'appimagetool': {'executable': 'appimagetool'}}
        calls = []
        def run(command, cwd):
            calls.append(command)
            if command[0] == 'appimagetool':
                self.assertIn('--runtime-file', command)
                tree = Path(command[-2])
                self.assertIn('LD_LIBRARY_PATH', (tree / 'AppRun').read_text())
                self.assertTrue((tree / '.DirIcon').is_symlink())
                data = bytearray(runtime.read_bytes())
                data[8:11] = b'AI\x02'
                Path(command[-1]).write_bytes(data)
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value=tools), patch.dict('os.environ', {'BLUEPRINT_APPIMAGE_RUNTIME': str(runtime)}), patch('tool.blueprint_environment.sys.platform', 'linux'):
            evidence = package_native('AppImage', source, stage, self.app, manifest, 'demo', run)
        self.assertEqual([c[0] for c in calls], ['linuxdeploy', 'appimagetool'])
        self.assertIn('sha256', evidence['runtime'])
        self.assertFalse((stage / '.work').exists())

    def test_appimage_missing_runtime_fails_without_package(self):
        source, stage, manifest = self.native_fixture('linux')
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value={}), patch.dict('os.environ', {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'BLUEPRINT_APPIMAGE_RUNTIME'):
                package_native('AppImage', source, stage, self.app, manifest, 'demo', lambda c, d: None)
        self.assertEqual(list(stage.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
