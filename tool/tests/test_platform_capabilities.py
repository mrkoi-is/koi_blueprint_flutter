import plistlib
from pathlib import Path
import tempfile
import unittest
from tool.platform_capabilities import plan_native_changes

_PBX = '''// !$*UTF8*$!
{
\tobjects = {
\t\t111111111111111111111111 = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t};
\t\t222222222222222222222222 /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t};
\t\t333333333333333333333333 /* Runner */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildPhases = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t};
\t\t444444444444444444444444 /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tmainGroup = 111111111111111111111111;
\t\t\tproductRefGroup = 222222222222222222222222 /* Products */;
\t\t\ttargets = (
\t\t\t\t333333333333333333333333 /* Runner */,
\t\t\t);
\t\t};
\t\t555555555555555555555555 = { isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.probe;};};
\t\t666666666666666666666666 = { isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.probe;};};
\t\t777777777777777777777777 = { isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.probe;};};
\t};
}
'''

class NativeCapabilitiesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app = Path(self.tmp.name)
        self.write('android/app/src/main/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="App"><activity android:name=".MainActivity" /></application></manifest>')
        self.write('android/app/src/main/kotlin/com/example/probe/MainActivity.kt', 'package com.example.probe\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity : FlutterActivity()\n')
        self.write('ios/Runner/Info.plist', plistlib.dumps({'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)'}))
        self.write('ios/Runner.xcodeproj/project.pbxproj', _PBX)

    def write(self, key, value):
        target = self.app / key
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(value if isinstance(value, bytes) else value.encode())

    def test_plan_is_read_only_and_apply_is_idempotent(self):
        original = {str(p): p.read_bytes() for p in self.app.rglob('*') if p.is_file()}
        changes = plan_native_changes(self.app, ['system-media', 'home-widget'])
        self.assertEqual(original, {str(p): p.read_bytes() for p in self.app.rglob('*') if p.is_file()})
        self.assertIn(b'AudioServiceActivity', changes['android/app/src/main/kotlin/com/example/probe/MainActivity.kt'])
        self.assertIn(b'PBXCopyFilesBuildPhase', changes['ios/Runner.xcodeproj/project.pbxproj'])
        self.assertIn(b'com.apple.product-type.app-extension', changes['ios/Runner.xcodeproj/project.pbxproj'])
        for key, value in changes.items(): self.write(key, value)
        self.assertEqual(changes, plan_native_changes(self.app, ['system-media', 'home-widget']))

    def test_edited_native_outputs_are_not_overwritten(self):
        self.write('ios/KoiHomeWidget/KoiHomeWidget.swift', '// user code')
        with self.assertRaisesRegex(ValueError, 'user changes'):
            plan_native_changes(self.app, ['home-widget'])

    def test_windows_audio_policy_is_opt_in_transactional_and_idempotent(self):
        original = 'cmake_minimum_required(VERSION 3.14)\nproject(probe LANGUAGES CXX)\ncmake_policy(VERSION 3.14...3.25)\n'
        self.write('windows/CMakeLists.txt', original)
        self.assertNotIn('windows/CMakeLists.txt', plan_native_changes(self.app, []))
        changes = plan_native_changes(self.app, ['system-media'])
        value = changes['windows/CMakeLists.txt']
        self.assertEqual((self.app / 'windows/CMakeLists.txt').read_text(), original)
        self.assertIn(b'cmake_minimum_required(VERSION 3.15)', value)
        self.assertLess(value.index(b'cmake_policy(SET CMP0091 NEW)'), value.index(b'project('))
        self.write('windows/CMakeLists.txt', value)
        self.assertEqual(value, plan_native_changes(self.app, ['system-media'])['windows/CMakeLists.txt'])
        self.write('windows/CMakeLists.txt', value.replace(b'CMP0091 NEW', b'CMP0091 OLD'))
        with self.assertRaisesRegex(ValueError, 'Edited managed Windows'):
            plan_native_changes(self.app, ['system-media'])

    def test_unknown_runner_anchor_is_rejected(self):
        self.write('ios/Runner.xcodeproj/project.pbxproj', _PBX.replace('mainGroup =', 'unrecognizedGroup ='))
        with self.assertRaisesRegex(ValueError, 'anchors'):
            plan_native_changes(self.app, ['home-widget'])

    def test_custom_app_group_is_shared_by_both_targets_and_dart(self):
        changes = plan_native_changes(self.app, ['home-widget'], {'home-widget': {'appGroup': 'group.example.shared'}})
        for path in ['ios/KoiHomeWidget/KoiHomeWidget.entitlements', 'ios/Runner/Runner.entitlements']:
            self.assertEqual(plistlib.loads(changes[path])['com.apple.security.application-groups'], ['group.example.shared'])
        self.assertIn(b'group.example.shared', changes['ios/KoiHomeWidget/KoiHomeWidget.swift'])
        self.assertIn(b'group.example.shared', changes['lib/features/home_widget/data/home_widget_configuration.dart'])

    def test_unmanaged_media_configuration_is_rejected(self):
        self.write('android/app/src/main/AndroidManifest.xml', '<manifest><application><service android:name="com.ryanheise.audioservice.AudioService" /></application></manifest>')
        with self.assertRaisesRegex(ValueError, 'Unmanaged'):
            plan_native_changes(self.app, ['system-media'])

    def test_network_release_permissions_are_opt_in_and_preserve_existing(self):
        for name in ['DebugProfile.entitlements', 'Release.entitlements']:
            self.write(f'macos/Runner/{name}', plistlib.dumps({'com.apple.security.app-sandbox': True}))
        changes = plan_native_changes(self.app, ['network'])
        self.assertIn(b'android.permission.INTERNET', changes['android/app/src/main/AndroidManifest.xml'])
        self.assertNotIn(b'usesCleartextTraffic', changes['android/app/src/main/AndroidManifest.xml'])
        entitlements = plistlib.loads(changes['macos/Runner/Release.entitlements'])
        self.assertTrue(entitlements['com.apple.security.network.client'])
        self.assertNotIn('com.apple.security.network.server', entitlements)
        self.assertTrue(entitlements['com.apple.security.app-sandbox'])
        changes = plan_native_changes(self.app, ['lan'], {'lan': {'allowLocalHttp': True}})
        self.assertIn(b'usesCleartextTraffic="true"', changes['android/app/src/main/AndroidManifest.xml'])
        self.assertTrue(plistlib.loads(changes['macos/Runner/Release.entitlements'])['com.apple.security.network.server'])
        self.assertTrue(plistlib.loads(changes['ios/Runner/Info.plist'])['NSAppTransportSecurity']['NSAllowsLocalNetworking'])

    def test_native_permissions_refuse_explicit_user_denial(self):
        for name in ['DebugProfile.entitlements', 'Release.entitlements']:
            self.write(f'macos/Runner/{name}', plistlib.dumps({'com.apple.security.network.client': False}))
        with self.assertRaisesRegex(ValueError, 'explicit merge'):
            plan_native_changes(self.app, ['network'])

    def test_desktop_native_close_policy_preserves_cancellable_dart_exit(self):
        self.write('macos/Runner/AppDelegate.swift', """import Cocoa
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
""")
        changes = plan_native_changes(self.app, ['desktop-window'])
        delegate = changes['macos/Runner/AppDelegate.swift']
        self.assertIn(b'return false', delegate)
        self.assertIn(b'applicationShouldHandleReopen', delegate)
        self.write('macos/Runner/AppDelegate.swift', delegate)
        self.assertEqual(changes, plan_native_changes(self.app, ['desktop-window']))
        self.write('macos/Runner/AppDelegate.swift', delegate.replace(b'return false', b'return userPreference'))
        with self.assertRaisesRegex(ValueError, 'anchor'):
            plan_native_changes(self.app, ['desktop-window'])

if __name__ == '__main__': unittest.main()
