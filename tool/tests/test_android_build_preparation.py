"""Flutter 3.47 mode-aware registrant/classpath regression (no SDK resolution)."""
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
import zipfile

from tool.blueprint_build import build_target, ensure_android_abi_filter
from tool.blueprint_provenance import source_identity


class AndroidBuildPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / 'apps/demo_app'
        self.native = self.app / 'android'
        self.native.mkdir(parents=True)
        (self.root / '.fvmrc').write_text('{"flutter":"3.47.2"}')
        (self.root / 'pubspec.lock').write_text('locked runtime and integration_test\n')
        (self.app / 'pubspec.yaml').write_text('name: demo_app\nversion: 1.0.0+2\nresolution: workspace\ndev_dependencies:\n  integration_test:\n    sdk: flutter\n')
        (self.native / 'build.gradle.kts').write_text('// before SDK migration\n')
        self.registrant = self.native / 'app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
        self.registrant.parent.mkdir(parents=True)
        self.calls = []
        self.javac = None

    def register(self, include_dev):
        dev = 'new dev.flutter.plugins.integration_test.IntegrationTestPlugin();' if include_dev else ''
        self.registrant.write_text('package io.flutter.plugins;\npublic final class GeneratedPluginRegistrant {\n public static void register() {\n new RuntimePlugin();\n' + dev + '\n }\n}\n')

    def sdk_behavior(self, command, cwd):
        """Model SDK pub vs build-mode refresh and the release native classpath."""
        self.assertEqual(cwd, self.app)
        self.calls.append(list(command))
        if command[1:3] == ['pub', 'get']:
            self.assertIn('--enforce-lockfile', command)
            self.register(include_dev=True)
            (self.app / '.flutter-plugins-dependencies').write_text(json.dumps({'plugins': {'android': [{'name': 'integration_test', 'dev_dependency': True}]}}))
            return
        self.assertEqual(command[1:3], ['build', 'apk'])
        release = '--release' in command
        # flutter_command.dart regenerates mode-aware tooling only with pub enabled.
        if '--no-pub' not in command:
            self.register(include_dev=not release)
        if '--config-only' in command:
            (self.native / 'build.gradle.kts').write_text('// SDK migration complete\n')
            return
        if self.javac:
            self.compile_registrant(release)
        elif release and 'IntegrationTestPlugin' in self.registrant.read_text():
            raise RuntimeError('package dev.flutter.plugins.integration_test does not exist')
        artifact = self.app / ('build/app/outputs/flutter-apk/app-' + ('release' if release else 'debug') + '.apk')
        artifact.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(artifact, 'w') as archive:
            archive.writestr('lib/arm64-v8a/libapp.so', b'\x7fELF\x02\x01' + b'\0' * 12 + struct.pack('<H', 183))

    def compile_registrant(self, release):
        # Tiny Java stand-ins exercise the actual compiler's missing-class check;
        # these are not a Flutter/Android SDK build and do not resolve dependencies.
        source = self.app / 'build/java-fixture'
        source.mkdir(parents=True, exist_ok=True)
        runtime = source / 'RuntimePlugin.java'
        runtime.write_text('package io.flutter.plugins; public final class RuntimePlugin {}')
        inputs = [self.registrant, runtime]
        if not release:
            dev = source / 'IntegrationTestPlugin.java'
            dev.write_text('package dev.flutter.plugins.integration_test; public final class IntegrationTestPlugin {}')
            inputs.append(dev)
        result = subprocess.run([self.javac, '-d', str(source / 'classes'), *map(str, inputs)], capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise RuntimeError(result.stderr)

    def build(self, mode='release', runner=None):
        return build_target(self.app, self.root, SimpleNamespace(flutter='flutter'), 'android-' + mode,
                            {'platform': 'android', 'mode': mode}, runner or self.sdk_behavior)

    def test_release_refreshes_dev_registrant_before_native_compile(self):
        before = source_identity(self.root)
        manifest = self.build()
        self.assertNotIn('IntegrationTestPlugin', self.registrant.read_text())
        self.assertEqual(len(self.calls), 3)
        prepare = self.calls[1]
        self.assertIn('--release', prepare)
        self.assertIn('--config-only', prepare)
        self.assertIn('--pub', prepare)
        self.assertNotIn('--no-pub', prepare)
        self.assertIn('--no-pub', self.calls[2])
        self.assertNotIn('--config-only', self.calls[2])
        self.assertEqual(manifest['preBuildCommands'], self.calls[:2])
        self.assertNotEqual(before['sourceSha256'], manifest['source']['sourceSha256'])
        self.assertEqual(manifest['source'], source_identity(self.root))
        self.assertIn('apps/demo_app/android/build.gradle.kts', manifest['preparation']['changedInputs'])
        self.assertIn('--dart-define=BUILD_SOURCE=' + manifest['source']['sourceSha256'], self.calls[2])
        self.assertIn('koiAbi=arm64-v8a', self.calls[1])
        self.assertIn('koiAbi=arm64-v8a', self.calls[2])
        self.assertEqual(manifest['status'], 'PASS')

    def test_abi_filter_is_applied_once_and_frozen_with_native_inputs(self):
        gradle = self.app / 'android/app/build.gradle.kts'
        gradle.write_text('android {\n    defaultConfig {\n        versionName = flutter.versionName\n    }\n}\n')
        manifest = self.build()
        text = gradle.read_text()
        self.assertIn('val abi: String = requested', text)
        self.assertEqual(text.count('findProperty("koiAbi")'), 1)
        self.assertIn('apps/demo_app/android/app/build.gradle.kts', manifest['preparation']['changedInputs'])
        self.assertEqual(manifest['status'], 'PASS')
        ensure_android_abi_filter(self.app)
        self.assertEqual(gradle.read_text(), text)
        self.calls.clear()
        again = self.build()
        self.assertEqual(gradle.read_text(), text)
        self.assertNotIn('apps/demo_app/android/app/build.gradle.kts', again['preparation']['changedInputs'])
        self.assertEqual(again['status'], 'PASS')

    def test_debug_restores_dev_plugin_after_a_release_build(self):
        self.build()
        self.calls.clear()
        manifest = self.build('debug')
        self.assertIn('IntegrationTestPlugin', self.registrant.read_text())
        self.assertIn('--debug', self.calls[1])
        self.assertEqual(manifest['status'], 'PASS')

    def test_preparation_failure_lock_change_or_dart_edit_stops_before_compilation(self):
        for change in ('failure', 'lock', 'dart'):
            with self.subTest(change=change):
                self.calls.clear()
                def runner(command, cwd):
                    self.sdk_behavior(command, cwd)
                    if '--config-only' not in command:
                        return
                    if change == 'failure':
                        raise RuntimeError('SDK configuration failed')
                    file = self.root / 'pubspec.lock' if change == 'lock' else self.app / 'lib/main.dart'
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text('changed outside native preparation')
                with self.assertRaisesRegex((RuntimeError, ValueError), 'SDK configuration failed|Lockfile changed|Non-native source changed'):
                    self.build(runner=runner)
                self.assertEqual(len(self.calls), 2)
                manifest = json.loads((self.app / 'build/blueprint/android-release.json').read_text())
                self.assertEqual(manifest['status'], 'FAIL')
                self.assertEqual(manifest['preparation']['status'], 'FAIL')
                self.assertNotIn('command', manifest)

    def test_native_edit_after_mode_preparation_keeps_failed_manifest(self):
        def runner(command, cwd):
            self.sdk_behavior(command, cwd)
            if command[1:3] == ['build', 'apk'] and '--config-only' not in command:
                (self.native / 'build.gradle.kts').write_text('// concurrent native edit')
        with self.assertRaisesRegex(ValueError, 'Source or lockfile changed during build'):
            self.build(runner=runner)
        manifest = json.loads((self.app / 'build/blueprint/android-release.json').read_text())
        self.assertEqual(manifest['status'], 'FAIL')
        self.assertEqual(manifest['preparation']['status'], 'PASS')

    @unittest.skipUnless(shutil.which('javac'), 'Optional real Java compiler is unavailable')
    def test_real_javac_rejects_old_sequence_and_accepts_prepared_release(self):
        self.javac = shutil.which('javac')
        available = subprocess.run([self.javac, '-version'], capture_output=True, timeout=10)
        if available.returncode:
            self.skipTest('Java compiler launcher exists but no usable JDK is configured')
        # Reproduce exactly pub-get -> no-pub release with no mode-aware refresh.
        self.sdk_behavior(['flutter', 'pub', 'get', '--enforce-lockfile'], self.app)
        with self.assertRaisesRegex(RuntimeError, 'package dev.flutter.plugins.integration_test does not exist'):
            self.sdk_behavior(['flutter', 'build', 'apk', '--release', '--no-pub'], self.app)
        self.calls.clear()
        manifest = self.build()
        self.assertEqual(manifest['status'], 'PASS')
        self.assertNotIn('IntegrationTestPlugin', self.registrant.read_text())


if __name__ == '__main__':
    unittest.main()
