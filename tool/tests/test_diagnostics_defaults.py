import argparse
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import blueprint
from tool.platform_capabilities import plan_native_changes, _diagnostic_activity

class DiagnosticDefaultsTest(unittest.TestCase):
    def test_create_defaults_only_when_field_is_absent(self):
        for capabilities, expected in [(None, ['diagnostics']), ([], []), (['network'], ['network'])]:
            with tempfile.TemporaryDirectory() as directory:
                config = Path(directory) / 'config.json'
                config.write_text(json.dumps({'schema': 1, **({} if capabilities is None else {'capabilities': capabilities})}))
                args = argparse.Namespace(name='diag_probe', output=str(Path(directory)/'result'), org='com.example',
                    platforms='web', template='minimal', dry_run=True, config=str(config), display_name=None)
                with patch('builtins.print') as output:
                    blueprint.create(args)
                plan = json.loads(output.call_args.args[0])
                self.assertEqual(plan['configuration']['capabilities'], expected)

    def test_android_release_server_configuration_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            app=Path(directory)
            path=app/'android/app/src/main/AndroidManifest.xml'
            path.parent.mkdir(parents=True)
            path.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application></application></manifest>')
            activity = path.parent / 'kotlin/example/MainActivity.kt'
            activity.parent.mkdir(parents=True)
            activity.write_text('package example\nclass MainActivity : FlutterActivity()\n')
            changes=plan_native_changes(app,['diagnostics'])
            manifest=changes[path.relative_to(app).as_posix()]
            for token in [b'android.permission.INTERNET',b'FOREGROUND_SERVICE_CONNECTED_DEVICE',b'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',b'foregroundServiceType="connectedDevice"',b'stopWithTask="true"']:
                self.assertIn(token,manifest)
            self.assertNotIn(b'usesCleartextTraffic',manifest)
            self.assertIn(b'channel.name = name', changes[activity.relative_to(app).as_posix()])
            self.assertIn(b'getNotificationChannel("koi_diagnostics")', changes[activity.relative_to(app).as_posix()])
            for relative, content in changes.items():
                (app / relative).write_bytes(content)
            self.assertEqual(changes,plan_native_changes(app,['diagnostics']))

    def test_notification_channel_wiring_preserves_activity_base_and_rejects_custom_override(self):
        for base in ('FlutterActivity', 'AudioServiceActivity'):
            source = f'package example\nclass MainActivity : {base}() {{}}\n'
            result = _diagnostic_activity(source)
            self.assertIn(f'class MainActivity : {base}()', result)
            self.assertIn('super.configureFlutterEngine(flutterEngine)', result)
            self.assertNotIn('deleteNotificationChannel', result)
            self.assertEqual(_diagnostic_activity(result), result)
        with self.assertRaisesRegex(ValueError, 'explicit diagnostics channel merge'):
            _diagnostic_activity('class MainActivity : FlutterActivity() { fun custom() {} }')

if __name__ == '__main__': unittest.main()
