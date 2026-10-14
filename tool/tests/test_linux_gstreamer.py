import json
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.blueprint_capability_doctor import (
    GSTREAMER_DEBIAN_PACKAGES, GSTREAMER_MODULES, capability_doctor,
    gstreamer_doctor, probe_gstreamer_runtime, uses_audioplayers_linux,
)
from tool.blueprint_packagers import bundle_gstreamer, package_native


class LinuxGStreamerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / 'app'
        self.app.mkdir()
        (self.root / 'pubspec.lock').write_text('packages:\n  audioplayers:\n    version: "6.6.0"\n')
        self.spec('dependencies:\n  flutter:\n    sdk: flutter\n')

    def spec(self, value):
        (self.app / 'pubspec.yaml').write_text('name: app\n' + value)

    def elf(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        data = bytearray(64)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', data, 18, 62)
        path.write_bytes(data)
        path.chmod(0o755)
        return path

    def test_app_selection_ignores_another_members_lock_and_dev_dependencies(self):
        with patch('tool.blueprint_capability_doctor.gstreamer_doctor', side_effect=AssertionError('not selected')):
            result = capability_doctor(self.app, [], entries={}, platforms=['linux'], host='linux')
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['systemDependencies'], [])
        self.spec('dev_dependencies:\n  audioplayers: 6.6.0\n')
        self.assertFalse(uses_audioplayers_linux(self.app))
        self.spec('dependencies:\n  "audioplayers": 6.6.0\n')
        self.assertTrue(uses_audioplayers_linux(self.app))
        with patch('tool.blueprint_capability_doctor.gstreamer_doctor', side_effect=AssertionError('not Linux target')):
            result = capability_doctor(self.app, [], entries={}, platforms=['web', 'macos'], host='darwin')
        self.assertEqual(result['systemDependencies'], [])

    def test_resolved_app_plugin_is_detected_and_foreign_host_never_loads(self):
        (self.app / '.flutter-plugins-dependencies').write_text(json.dumps({'plugins': {'linux': [{'name': 'audioplayers_linux'}]}}))
        self.assertTrue(uses_audioplayers_linux(self.app))
        with patch('tool.blueprint_capability_doctor.subprocess.run', side_effect=AssertionError('wrong host')):
            result = capability_doctor(self.app, [], entries={}, platforms=['linux'], host='darwin')
        self.assertEqual(result['status'], 'INCOMPLETE')
        self.assertEqual(result['systemDependencies'][0]['status'], 'NOT_RUN')

    def test_pkg_config_and_runtime_are_separate_required_checks(self):
        self.spec('dependencies:\n  audioplayers: 6.6.0\n')
        with patch('tool.blueprint_capability_doctor.shutil.which', return_value='/usr/bin/pkg-config'), patch('tool.blueprint_capability_doctor.subprocess.run', return_value=subprocess.CompletedProcess([], 0, '1.24.2\n', '')) as process, patch('tool.blueprint_capability_doctor.probe_gstreamer_runtime', return_value={'status': 'LOADABLE'}):
            result = capability_doctor(self.app, [], entries={}, platforms=['linux'], host='linux')
            self.assertEqual(result['status'], 'PASS')
            self.assertEqual([call.args[0][-1] for call in process.call_args_list], list(GSTREAMER_MODULES))
        with patch('tool.blueprint_capability_doctor.shutil.which', return_value=None), patch('tool.blueprint_capability_doctor.probe_gstreamer_runtime', return_value={'status': 'LOADABLE'}):
            self.assertEqual(gstreamer_doctor('linux')['status'], 'FAIL')
        with patch('tool.blueprint_capability_doctor.shutil.which', return_value='/usr/bin/pkg-config'), patch('tool.blueprint_capability_doctor.subprocess.run', return_value=subprocess.CompletedProcess([], 0, '1.24.2\n', '')), patch('tool.blueprint_capability_doctor.probe_gstreamer_runtime', return_value={'status': 'NOT_LOADABLE', 'reason': 'missing playbin'}):
            self.assertEqual(gstreamer_doctor('linux')['status'], 'FAIL')

    def test_runtime_probe_is_child_process_and_preserves_failure(self):
        with patch('tool.blueprint_capability_doctor.subprocess.run', return_value=subprocess.CompletedProcess([], 1, '', 'Missing/unloadable GStreamer element: playbin')) as process:
            result = probe_gstreamer_runtime()
        self.assertEqual(result['status'], 'NOT_LOADABLE')
        self.assertIn('playbin', result['reason'])
        self.assertEqual(process.call_args.kwargs['env']['GST_REGISTRY_UPDATE'], 'no')
        self.assertIn('-c', process.call_args.args[0])

    def package_fixture(self):
        source = self.app / 'build/bundle'
        self.elf(source / 'app')
        stage = self.app / 'build/stage'
        stage.mkdir()
        manifest = {'version': '1.2.3', 'profile': {'platform': 'linux', 'arch': 'x64'}}
        return source, stage, manifest

    def test_deb_only_installed_engine_adds_dynamic_runtime_packages(self):
        for installed in (False, True):
            with self.subTest(installed=installed):
                self.spec('dependencies:\n  audioplayers: 6.6.0\n' if installed else 'dependencies:\n  flutter:\n    sdk: flutter\n')
                source, stage, manifest = self.package_fixture()
                tools = {'dpkg': {'executable': 'dpkg-deb'}, 'shlibdeps': {'executable': 'dpkg-shlibdeps'}}
                controls = []
                def run(command, cwd):
                    controls.append((Path(command[-2]) / 'DEBIAN/control').read_text())
                    Path(command[-1]).write_bytes(b'!<arch>\narchive')
                inferred = 'shlibs:Depends=libc6 (>= 2.34), libgstreamer1.0-0 (>= 1.20)\n' if installed else 'shlibs:Depends=libc6 (>= 2.34)\n'
                with patch('tool.blueprint_packagers.require_packaging_tools', return_value=tools), patch('tool.blueprint_packagers.subprocess.run', return_value=subprocess.CompletedProcess([], 0, inferred, '')):
                    evidence = package_native('deb', source, stage, self.app, manifest, 'app', run)
                for name in GSTREAMER_DEBIAN_PACKAGES:
                    self.assertEqual(name in controls[0], installed)
                self.assertEqual(controls[0].count('libgstreamer1.0-0'), int(installed))
                self.assertEqual(evidence['dependencyAnalysis']['explicitRuntimePackages'], list(GSTREAMER_DEBIAN_PACKAGES) if installed else [])
                import shutil
                shutil.rmtree(self.app / 'build')

    def gstreamer_fixture(self):
        tree = self.root / 'AppDir'
        tree.mkdir()
        plugins = self.root / 'gst-plugins'
        for name in ('libgstplayback.so', 'libgstaudiofx.so', 'libgstautodetect.so'):
            self.elf(plugins / name)
        scanner_dir = self.root / 'gst-libexec'
        self.elf(scanner_dir / 'gst-plugin-scanner')
        def pkg(command, **kwargs):
            location = plugins if '--variable=pluginsdir' in command else scanner_dir
            return subprocess.CompletedProcess(command, 0, str(location), '')
        def probe(*, environment_overrides):
            env = environment_overrides
            self.assertEqual(env['GST_PLUGIN_SYSTEM_PATH_1_0'], '')
            self.assertEqual(env['GST_PLUGIN_SYSTEM_PATH'], '')
            self.assertTrue(Path(env['GST_PLUGIN_SCANNER_1_0']).is_file())
            files = sorted(str(p.resolve()) for p in (tree / 'usr/lib/gstreamer-1.0').glob('*.so'))
            libraries = [{'soname': name, 'path': str(self.elf(tree / 'usr/lib' / name))} for name in ('libgstreamer-1.0.so.0', 'libgstapp-1.0.so.0', 'libgstaudio-1.0.so.0')]
            return {'status': 'LOADABLE', 'verifiedPlugins': files, 'libraries': libraries,
                    'elementPlugins': [{'element': name, 'path': files[i % len(files)]} for i, name in enumerate(('playbin', 'audioconvert', 'audioresample', 'wavparse', 'autoaudiosink', 'audiopanorama'))]}
        return tree, plugins, scanner_dir, pkg, probe

    def test_appimage_collects_plugins_scanner_and_verifies_only_bundle_paths(self):
        tree, plugins, scanner_dir, pkg, probe = self.gstreamer_fixture()
        calls = []
        with patch('tool.blueprint_packagers.gstreamer_doctor', return_value={'status': 'PASS'}), patch('tool.blueprint_packagers.shutil.which', return_value='/usr/bin/pkg-config'), patch('tool.blueprint_packagers.subprocess.run', side_effect=pkg), patch('tool.blueprint_packagers.probe_gstreamer_runtime', side_effect=probe):
            evidence = bundle_gstreamer(tree, {'linuxdeploy': {'executable': 'linuxdeploy'}}, self.app, 'x64', lambda command, cwd: calls.append(command))
        self.assertEqual(evidence['status'], 'VERIFIED')
        self.assertEqual(len(evidence['files']), 4)
        self.assertEqual(calls[0].count('--library'), 3)
        self.assertIn('--executable', calls[0])
        self.assertTrue(all(item['bundledSha256'] for item in evidence['files']))

    def test_appimage_rejects_missing_scanner_unloadable_or_host_plugin_closure(self):
        for failure in ('scanner', 'scanner_dependency', 'architecture', 'load', 'host', 'omitted', 'mutation'):
            with self.subTest(failure=failure):
                tree, plugins, scanner_dir, pkg, probe = self.gstreamer_fixture()
                if failure == 'scanner': (scanner_dir / 'gst-plugin-scanner').unlink()
                if failure == 'architecture':
                    data = bytearray((plugins / 'libgstplayback.so').read_bytes())
                    struct.pack_into('<H', data, 18, 183)
                    (plugins / 'libgstplayback.so').write_bytes(data)
                def deploy(command, cwd):
                    if failure == 'mutation':
                        with (plugins / 'libgstplayback.so').open('ab') as output: output.write(b'changed')
                def checked_pkg(command, **kwargs):
                    if failure == 'scanner_dependency' and 'gst-plugin-scanner' in str(command[-1]):
                        return subprocess.CompletedProcess(command, 0, 'libmissing.so => not found', '')
                    return pkg(command, **kwargs)
                def broken_probe(**kwargs):
                    value = probe(**kwargs)
                    if failure == 'load': return {'status': 'NOT_LOADABLE', 'reason': 'missing dependency'}
                    if failure == 'host': value['elementPlugins'][0]['path'] = '/usr/lib/gstreamer-1.0/libgstplayback.so'
                    if failure == 'omitted': value['verifiedPlugins'] = []
                    return value
                with patch('tool.blueprint_packagers.gstreamer_doctor', return_value={'status': 'PASS'}), patch('tool.blueprint_packagers.shutil.which', return_value='/usr/bin/pkg-config'), patch('tool.blueprint_packagers.subprocess.run', side_effect=checked_pkg), patch('tool.blueprint_packagers.probe_gstreamer_runtime', side_effect=broken_probe):
                    with self.assertRaises(ValueError):
                        bundle_gstreamer(tree, {'linuxdeploy': {'executable': 'linuxdeploy'}}, self.app, 'x64', deploy)
                import shutil
                for path in (tree, plugins, scanner_dir): shutil.rmtree(path)

    def test_selected_appimage_launcher_and_manifest_use_verified_plugin_environment(self):
        self.spec('dependencies:\n  audioplayers: 6.6.0\n')
        source, stage, manifest = self.package_fixture()
        runtime = self.elf(self.root / 'runtime')
        content = bytearray(runtime.read_bytes()); content[8:11] = b'AI\x02'; runtime.write_bytes(content)
        runtime_evidence = {'path': str(runtime), 'sha256': hashlib.sha256(content).hexdigest()}
        tools = {'linuxdeploy': {'executable': 'linuxdeploy'}, 'appimagetool': {'executable': 'appimagetool'}}
        def run(command, cwd):
            if command[0] == 'appimagetool':
                launcher = (Path(command[-2]) / 'AppRun').read_text()
                self.assertIn('GST_PLUGIN_PATH_1_0=', launcher)
                self.assertIn('GST_PLUGIN_SYSTEM_PATH_1_0=""', launcher)
                self.assertIn('GST_PLUGIN_SCANNER_1_0=', launcher)
                Path(command[-1]).write_bytes(content)
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value=tools), patch('tool.blueprint_packagers.require_appimage_runtime', return_value=runtime_evidence), patch('tool.blueprint_packagers.bundle_gstreamer', return_value={'status': 'VERIFIED', 'files': ['fixture']}) as bundle:
            result = package_native('AppImage', source, stage, self.app, manifest, 'app', run)
        self.assertEqual(result['gstreamer']['status'], 'VERIFIED')
        self.assertEqual(bundle.call_count, 1)
        self.assertTrue((stage / 'app.AppImage').is_file())

    def test_failed_gstreamer_closure_never_invokes_appimagetool_or_leaves_package(self):
        self.spec('dependencies:\n  audioplayers: 6.6.0\n')
        source, stage, manifest = self.package_fixture()
        runtime = self.elf(self.root / 'runtime')
        content = bytearray(runtime.read_bytes()); content[8:11] = b'AI\x02'; runtime.write_bytes(content)
        tools = {'linuxdeploy': {'executable': 'linuxdeploy'}, 'appimagetool': {'executable': 'appimagetool'}}
        commands = []
        with patch('tool.blueprint_packagers.require_packaging_tools', return_value=tools), patch('tool.blueprint_packagers.require_appimage_runtime', return_value={'path': str(runtime), 'sha256': 'unused'}), patch('tool.blueprint_packagers.bundle_gstreamer', side_effect=ValueError('plugin closure missing')):
            with self.assertRaisesRegex(ValueError, 'plugin closure'):
                package_native('AppImage', source, stage, self.app, manifest, 'app', lambda c, d: commands.append(c))
        self.assertEqual([c[0] for c in commands], ['linuxdeploy'])
        self.assertEqual(list(stage.iterdir()), [])


if __name__ == '__main__': unittest.main()
