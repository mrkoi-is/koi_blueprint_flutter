import plistlib
from pathlib import Path
import tempfile
import unittest
from tool.device_capabilities import plan_device_changes
from tool.platform_capabilities import plan_native_changes

class DeviceWiringTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.app=Path(self.temp.name)
        self.write('android/app/src/main/AndroidManifest.xml','<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application><activity android:name=".MainActivity" android:exported="true"></activity></application></manifest>')
        self.write('android/app/src/main/kotlin/test/MainActivity.kt','package test\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity : FlutterActivity()\n')
        for platform in ['ios','macos']:
            self.write(f'{platform}/Runner/Info.plist',plistlib.dumps({'CFBundleIdentifier':'test.app'}))
        for name in ['DebugProfile.entitlements','Release.entitlements']:
            self.write(f'macos/Runner/{name}',plistlib.dumps({'com.apple.security.app-sandbox':True}))
        self.write('macos/Runner/AppDelegate.swift','import Cocoa\nimport FlutterMacOS\n@main\nclass AppDelegate: FlutterAppDelegate {\n}\n')
        self.write('windows/runner/main.cpp','#include "utils.h"\nint APIENTRY wWinMain() {\n  // Attach to console when present\n}\n')
        self.write('windows/CMakeLists.txt','cmake_minimum_required(VERSION 3.14)\ncmake_policy(VERSION 3.14...3.25)\n')
        self.write('linux/runner/my_application.cc','''static void my_application_activate(GApplication* application) {
  GtkWindow* window = make_window();
}
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  *exit_status = 0;

  return TRUE;
}
// Implements GObject::dispose.
int flags = G_APPLICATION_NON_UNIQUE;
''')
    def write(self,path,value):
        p=self.app/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value.encode() if isinstance(value,str) else value)
    def test_read_only_overlay_and_reinstall(self):
        before={p:p.read_bytes() for p in self.app.rglob('*') if p.is_file()}
        base=plan_native_changes(self.app,['system-media'])
        changes=plan_device_changes(self.app,['incoming-intents','system-media'],base_changes=base)
        self.assertEqual(before,{p:p.read_bytes() for p in self.app.rglob('*') if p.is_file()})
        android=changes['android/app/src/main/AndroidManifest.xml']
        self.assertIn(b'AudioService',android);self.assertIn(b'android.intent.action.SEND',android)
        kotlin=changes['android/app/src/main/kotlin/test/MainActivity.kt']
        self.assertIn(b'AudioServiceActivity',kotlin);self.assertIn(b'contentResolver.openInputStream',kotlin)
        self.assertIn(b'256 * 1024',kotlin)
        self.assertIn(b'openFiles filenames',changes['macos/Runner/AppDelegate.swift'])
        self.assertIn(b'SendAppLinkToInstance()',changes['windows/runner/main.cpp'])
        self.assertIn(b'return FALSE;',changes['linux/runner/my_application.cc'])
        for path,data in {**base,**changes}.items():self.write(path,data)
        self.assertEqual(changes,plan_device_changes(self.app,['incoming-intents']))
    def test_configuration_and_edits_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'supports the koi'):
            plan_device_changes(self.app,['incoming-intents'],{'incoming-intents':{'scheme':'other'}})
        changes=plan_device_changes(self.app,['incoming-intents'])
        for path,data in changes.items():self.write(path,data)
        self.write('windows/runner/main.cpp',changes['windows/runner/main.cpp'].replace(b'SendAppLinkToInstance()',b'custom()'))
        with self.assertRaisesRegex(ValueError,'Edited managed'):
            plan_device_changes(self.app,['incoming-intents'])
    def test_onboarding_does_not_wire_native_network_or_links(self):
        self.assertEqual(plan_device_changes(self.app,['onboarding']),{})
    def test_runner_symlink_is_rejected(self):
        path=self.app/'macos/Runner/Info.plist';path.unlink();path.symlink_to(self.app/'ios/Runner/Info.plist')
        with self.assertRaisesRegex(ValueError,'symlink'):
            plan_device_changes(self.app,['incoming-intents'])
