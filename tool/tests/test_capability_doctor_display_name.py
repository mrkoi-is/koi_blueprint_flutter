import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from tool.blueprint_capability_doctor import capability_doctor, matches_version, probe_native_library, native_candidates
from tool.blueprint_display_name import plan_display_name

ROOT = Path(__file__).resolve().parents[2]
EXAMPLES = ROOT / 'examples'
if not (EXAMPLES / 'platform_lab').is_dir():
    EXAMPLES = ROOT / '.blueprint/reference/examples'


class DisplayNameTest(unittest.TestCase):
    def test_six_platforms_escape_idempotence_and_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            files = ['android/app/src/main/AndroidManifest.xml', 'ios/Runner/Info.plist', 'macos/Runner/Info.plist', 'macos/Runner/Base.lproj/MainMenu.xib', 'windows/runner/main.cpp', 'windows/runner/Runner.rc', 'linux/runner/my_application.cc', 'web/manifest.json', 'web/index.html']
            for relative in files:
                source = EXAMPLES / 'platform_lab' / relative
                target = app / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            before = {relative: (app / relative).read_bytes() for relative in files}
            name = '锦鲤 "Studio" & <工具> \\ 𝄞'
            platforms = ['android', 'ios', 'macos', 'windows', 'linux', 'web']
            changes = plan_display_name(app, name, platforms)
            self.assertEqual(before, {relative: (app / relative).read_bytes() for relative in files}, 'planning must not mutate input')
            for relative, content in changes.items(): (app / relative).write_bytes(content)
            self.assertEqual(plan_display_name(app, name, platforms), {})
            android = ET.fromstring((app / files[0]).read_bytes()).find('application')
            self.assertEqual(android.get('{http://schemas.android.com/apk/res/android}label'), name)
            for platform in ['ios', 'macos']:
                relative = platform + '/Runner/Info.plist'
                old, new = plistlib.loads(before[relative]), plistlib.loads((app / relative).read_bytes())
                self.assertEqual(new['CFBundleDisplayName'], name)
                self.assertEqual(new['CFBundleName'], name)
                self.assertEqual(new['CFBundleIdentifier'], old['CFBundleIdentifier'])
            windows = (app / 'windows/runner/main.cpp').read_text()
            self.assertIn(r'\U0001d11e', windows)
            self.assertIn(r'\"Studio\"', windows)
            rc = (app / 'windows/runner/Runner.rc').read_text()
            self.assertIn('锦鲤', rc)
            self.assertIn('#pragma code_page(65001)', rc)
            self.assertIn('"platform_lab.exe"', rc)
            self.assertEqual(json.loads((app / 'web/manifest.json').read_text())['name'], name)
            self.assertIn('&lt;工具&gt;', (app / 'web/index.html').read_text())
            xib = ET.fromstring((app / 'macos/Runner/Base.lproj/MainMenu.xib').read_bytes())
            window = next(element for element in xib.iter('window') if element.get('customClass') == 'MainFlutterWindow')
            self.assertEqual(window.get('title'), name)

    def test_invalid_missing_and_symlink_inputs_are_rejected_without_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            for name in ['', '\nName', '\ud800', 'a' * 81]:
                with self.assertRaises(ValueError): plan_display_name(app, name, [])
            with self.assertRaises(ValueError): plan_display_name(app, 'Name', ['web'])
            (app / 'web').symlink_to(EXAMPLES / 'platform_lab/web', target_is_directory=True)
            with self.assertRaises(ValueError): plan_display_name(app, 'Name', ['web'])


class CapabilityDoctorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / 'apps/demo'
        self.app.mkdir(parents=True)
        (self.root / 'pubspec.lock').write_text('packages:\n  drift:\n    dependency: direct main\n    version: "2.35.1"\n  sqlite3:\n    dependency: direct main\n    version: "3.7.0"\n')
        self.entries = {'database': {'dependencies': [], 'pubspecDependencies': {'drift': '2.35.1', 'sqlite3': '3.7.0'}}}

    def doctor(self, **kwargs):
        return capability_doctor(self.app, ['database'], entries=self.entries, **kwargs)

    def test_missing_library_is_not_runtime_pass_and_other_targets_never_probe(self):
        result = self.doctor(host='darwin', platforms=['macos', 'windows', 'android', 'ios'])
        self.assertEqual(result['status'], 'INCOMPLETE')
        self.assertEqual({item['status'] for item in result['nativeLibraries']}, {'NOT_RUN'})
        self.assertEqual({item['status'] for item in result['dependencies']}, {'MATCH'})
        target = self.app / 'build/windows/sqlite3.dll'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'invalid library')
        with patch('tool.blueprint_capability_doctor.probe_native_library', side_effect=AssertionError('foreign library must not execute')):
            self.assertEqual(self.doctor(host='darwin', platforms=['windows'])['status'], 'INCOMPLETE')

    def test_existing_invalid_native_library_fails_actual_child_process_load(self):
        target = self.app / 'build/native_assets/macos/libsqlite3.dylib'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'not a native library')
        result = self.doctor(host='darwin', platforms=['macos'])
        self.assertEqual(result['status'], 'FAIL')
        loaded = result['nativeLibraries'][0]['libraries'][0]
        self.assertEqual(loaded['status'], 'NOT_LOADABLE')
        self.assertEqual(loaded['sha256'], hashlib.sha256(target.read_bytes()).hexdigest())

    def test_web_pinned_hash_versions_and_runtime_are_separate(self):
        web = self.app / 'web'
        web.mkdir()
        entries = []
        for path, data in [('sqlite3.wasm', b'\0asm\x01\0\0\0'), ('drift_worker.dart.js', b'worker')]:
            (web / path).write_bytes(data)
            entries.append({'path': path, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        manifest = {'drift': '2.35.1', 'sqlite3': '3.7.0', 'assets': entries}
        (web / 'drift-assets.json').write_text(json.dumps(manifest))
        result = self.doctor(platforms=['web'])
        self.assertEqual(result['status'], 'INCOMPLETE')
        self.assertEqual(result['webAssets'][0]['status'], 'VERIFIED_ASSETS')
        self.assertEqual(result['webAssets'][0]['runtime'], 'NOT_RUN')
        (web / 'sqlite3.wasm').write_bytes(b'tampered')
        self.assertEqual(self.doctor(platforms=['web'])['status'], 'FAIL')
        manifest['sqlite3'] = '3.8.0'
        (web / 'drift-assets.json').write_text(json.dumps(manifest))
        self.assertIn('version differs', self.doctor(platforms=['web'])['webAssets'][0]['reason'])

    def test_dependency_mismatch_and_unknown_capability(self):
        self.entries['database']['pubspecDependencies']['sqlite3'] = '3.8.0'
        self.assertEqual(self.doctor(platforms=[])['status'], 'FAIL')
        with self.assertRaises(ValueError): capability_doctor(self.app, ['missing'], entries=self.entries)
        self.assertTrue(matches_version('1.9.2', '^1.9.1'))
        self.assertFalse(matches_version('2.0.0', '^1.9.1'))
        self.assertFalse(matches_version('0.3.0', '^0.2.4'))
        self.assertFalse(matches_version('3.8.0-beta', '^3.7.0'))

    def test_only_runtime_bundle_candidates_exclude_sdk_intermediates(self):
        intermediate = self.app / 'build/macos/Build/Products/Release/XCFrameworkIntermediates/media/Mpv.framework/Versions/A/Mpv'
        runtime = self.app / 'build/macos/Build/Products/Release/demo.app/Contents/Frameworks/Mpv.framework/Versions/A/Mpv'
        for path in [intermediate, runtime]:
            path.parent.mkdir(parents=True)
            path.write_bytes(b'fixture')
        self.assertEqual(native_candidates(self.app, 'macos', 'media'), [runtime.resolve()])

    def test_actual_app_mpv_headless_initialization_if_built(self):
        candidates = native_candidates(EXAMPLES / 'platform_lab', 'macos', 'media')
        if not candidates: self.skipTest('platform Lab macOS media build product unavailable')
        for path in candidates:
            result = probe_native_library('media', path)
            self.assertEqual(result['status'], 'LOADABLE', result)
            self.assertEqual(result['operation'], 'headless engine initialization')
            self.assertTrue(result['loaderSearchPaths'])

    def test_actual_app_sqlite_load_if_built(self):
        path = EXAMPLES / 'database_lab/build/native_assets/macos/libsqlite3.dylib'
        if not path.is_file(): self.skipTest('database Lab native SQLite build product unavailable')
        result = probe_native_library('sqlite', path)
        self.assertEqual(result['status'], 'LOADABLE', result)
        self.assertEqual(result['operation'], 'in-memory SQL')
        self.assertRegex(result['libraryVersion'], r'^3\.')


if __name__ == '__main__': unittest.main()
