import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.blueprint_capabilities import FileTransaction, atomic_write, install_plan, resolve, snapshot_install_inputs
from tool.blueprint_config import read_config, choose, validate_profile
from tool.blueprint_provenance import plan_install_baseline, source_identity, upgrade_report
from tool.blueprint_build import describe_artifact, verify_architecture
from tool.platform_evidence import source_manifest


class UpgradeToolsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='blueprint-upgrade-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else value.encode())
        return path

    def test_config_rejects_unknown_fields_conflicting_flags_and_invalid_arch(self):
        config = self.write('config.json', json.dumps({'schema': 1, 'unknown': True}))
        with self.assertRaises(ValueError): read_config(config)
        with self.assertRaises(ValueError): choose('minimal', {'template': 'workbench'}, 'template')
        with self.assertRaises(ValueError): validate_profile({'platform': 'ios', 'arch': 'x64'})
        self.assertEqual(validate_profile({'platform': 'macos'})['arch'], 'arm64')

    def test_dependency_order_deduplicates_and_rejects_cycles(self):
        entries = {'a': {'dependencies': ['b']}, 'b': {}}
        self.assertEqual(resolve(['a', 'b'], entries), ['b', 'a'])
        entries['b']['dependencies'] = ['a']
        with self.assertRaises(ValueError): resolve(['a'], entries)
        with self.assertRaises(ValueError): resolve(['unknown'], entries)

    def test_transaction_rolls_back_exact_bytes_and_created_directories(self):
        old = self.write('original.txt', b'original\r\n')
        operation = FileTransaction(self.root, {'new/sub/file.txt': b'new', 'original.txt': b'changed'})
        def fail(path, value):
            if path == old.resolve(): raise OSError('disk full')
            atomic_write(path, value)
        with patch('tool.blueprint_capabilities.atomic_write', side_effect=fail), self.assertRaises(OSError):
            operation.commit()
        self.assertEqual(old.read_bytes(), b'original\r\n')
        self.assertFalse((self.root / 'new').exists())
        self.assertFalse((self.root / '.blueprint-install.lock').exists())

    def test_transaction_preserves_concurrent_edits_even_when_followup_fails(self):
        original = self.write('file.txt', 'old')
        operation = FileTransaction(self.root, {'file.txt': b'ours'})
        def followup():
            original.write_bytes(b'user concurrent edit')
            raise OSError('validation failed')
        with self.assertRaises(OSError): operation.commit(followup)
        self.assertEqual(original.read_bytes(), b'user concurrent edit')
        operation = FileTransaction(self.root, {'file.txt': b'next'})
        original.write_bytes(b'another edit')
        with self.assertRaises(ValueError): operation.commit()
        self.assertEqual(original.read_bytes(), b'another edit')

    def test_install_rejects_edit_between_plan_and_transaction_snapshot(self):
        app = self.root / 'apps/demo'
        file = self.write('apps/demo/pubspec.yaml', 'before')
        snapshot = snapshot_install_inputs(self.root, app)
        file.write_text('user edit after plan started')
        with self.assertRaisesRegex(ValueError, 'changed while planning'):
            FileTransaction(self.root, {'apps/demo/pubspec.yaml': b'installer output'},
                            expected_hashes=snapshot)
        self.assertEqual(file.read_text(), 'user edit after plan started')

    def test_symlink_and_path_escape_are_rejected(self):
        with self.assertRaises(ValueError): FileTransaction(self.root, {'../escape': b'x'})
        (self.root / 'link').symlink_to(self.root)
        with self.assertRaises(ValueError): FileTransaction(self.root, {'link/file': b'x'})

    def test_upgrade_report_uses_source_baseline_distinct_from_generated_name(self):
        source = self.root / 'upstream'
        current = self.root / 'project'
        source.mkdir(); current.mkdir()
        (source / 'template.dart').write_text('class Starter {}')
        (current / 'app.dart').write_text('class Demo {}')
        metadata = {'schema': 2, 'managedFiles': {'app.dart': {'source': 'template.dart',
            'sha256': hashlib.sha256(b'class Demo {}').hexdigest(),
            'sourceSha256': hashlib.sha256(b'class Starter {}').hexdigest()}}}
        (current / 'blueprint.json').write_text(json.dumps(metadata))
        self.assertEqual(len(upgrade_report(current, source)['unchanged']), 1)
        (source / 'template.dart').write_text('class Starter { final x = 1; }')
        self.assertEqual(len(upgrade_report(current, source)['upstreamChanges']), 1)
        (current / 'app.dart').write_text('class Demo { final user = 1; }')
        before = (current / 'app.dart').read_bytes()
        self.assertEqual(len(upgrade_report(current, source)['conflicts']), 1)
        self.assertEqual((current / 'app.dart').read_bytes(), before)

    def test_upgrade_report_recognizes_identical_upstream_fix_already_applied(self):
        source = self.root / 'upstream'
        project = self.root / 'project'
        recipe = source / 'tool/capabilities/recipes/demo/lib'
        recipe.mkdir(parents=True)
        local = project / 'apps/demo_app/lib/feature.dart'
        local.parent.mkdir(parents=True)
        recipe_file = recipe / 'feature.dart'
        recipe_file.write_text('import "package:__APP_PACKAGE__/old.dart";')
        local.write_text('import "package:demo_app/old.dart";')
        metadata = {'schema': 2, 'app': 'apps/demo_app', 'managedFiles': {
            'apps/demo_app/lib/feature.dart': {
                'source': 'tool/capabilities/recipes/demo/lib/feature.dart',
                'sha256': hashlib.sha256(local.read_bytes()).hexdigest(),
                'sourceSha256': hashlib.sha256(recipe_file.read_bytes()).hexdigest(),
            },
        }}
        (project / 'blueprint.json').write_text(json.dumps(metadata))
        recipe_file.write_text('import "package:__APP_PACKAGE__/fixed.dart";')
        local.write_text('import "package:demo_app/fixed.dart";')
        report = upgrade_report(project, source)
        self.assertEqual([item['path'] for item in report['alreadyApplied']], ['apps/demo_app/lib/feature.dart'])
        self.assertEqual(report['conflicts'], [])

    def test_upgrade_report_recognizes_renamed_example_import_already_applied(self):
        source = self.root / 'upstream'
        project = self.root / 'project'
        upstream = source / 'examples/network_lab/lib/feature.dart'
        upstream.parent.mkdir(parents=True)
        upstream.write_text('import "package:network_lab/old.dart";')
        local = project / 'apps/demo_app/lib/feature.dart'
        local.parent.mkdir(parents=True)
        local.write_text('import "package:demo_app/old.dart";')
        metadata = {'schema': 2, 'app': 'apps/demo_app', 'managedFiles': {
            'apps/demo_app/lib/feature.dart': {
                'source': 'examples/network_lab/lib/feature.dart',
                'sha256': hashlib.sha256(local.read_bytes()).hexdigest(),
                'sourceSha256': hashlib.sha256(upstream.read_bytes()).hexdigest(),
            },
        }}
        (project / 'blueprint.json').write_text(json.dumps(metadata))
        upstream.write_text('import "package:network_lab/fixed.dart";')
        local.write_text('import "package:demo_app/fixed.dart";')
        report = upgrade_report(project, source)
        self.assertEqual([item['path'] for item in report['alreadyApplied']], ['apps/demo_app/lib/feature.dart'])
        self.assertEqual(report['conflicts'], [])

    def test_install_baseline_tracks_new_recipe_but_preserves_prior_user_edit(self):
        source = self.root / 'source'
        project = self.root / 'project'
        (source / 'recipe').mkdir(parents=True)
        (project / 'apps/demo').mkdir(parents=True)
        (source / 'recipe/feature.dart').write_text('upstream v1')
        (source / 'recipe/pubspec.yaml').write_text('upstream unchanged')
        original = project / 'apps/demo/pubspec.yaml'
        original.write_text('user custom dependencies')
        previous = {'managedFiles': {'apps/demo/pubspec.yaml': {
            'sha256': hashlib.sha256(b'original pubspec').hexdigest(),
            'source': 'recipe/pubspec.yaml',
            'sourceSha256': hashlib.sha256(b'upstream unchanged').hexdigest()}}}
        receipt = {'managedFiles': dict(previous['managedFiles']),
                   'capabilities': {'demo': {'files': {'apps/demo/feature.dart': ''},
                                              'origins': {'apps/demo/feature.dart': 'recipe/feature.dart'}}},
                   'nativeFiles': {'apps/demo/native.xml': ''}}
        changes = {'apps/demo/pubspec.yaml': b'user custom dependencies\n  demo: any',
                   'apps/demo/feature.dart': b'installed feature',
                   'apps/demo/native.xml': b'<native/>'}
        blobs = plan_install_baseline(project, source, previous, receipt, changes)
        self.assertEqual(receipt['managedFiles']['apps/demo/pubspec.yaml'], previous['managedFiles']['apps/demo/pubspec.yaml'])
        self.assertEqual(receipt['managedFiles']['apps/demo/feature.dart']['sourceSha256'],
                         hashlib.sha256(b'upstream v1').hexdigest())
        self.assertIsNone(receipt['managedFiles']['apps/demo/native.xml']['source'])
        self.assertEqual(len(blobs), 2)
        for relative, content in changes.items():
            path = project / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        (project / 'blueprint.json').write_text(json.dumps({'schema': 2, **receipt}))
        report = upgrade_report(project, source)
        self.assertIn('apps/demo/pubspec.yaml', [item['path'] for item in report['localChanges']])
        self.assertIn('apps/demo/native.xml', [item['path'] for item in report['unchanged']])
        (project / 'apps/demo/feature.dart').write_text('user feature edit')
        (source / 'recipe/feature.dart').write_text('upstream v2')
        report = upgrade_report(project, source)
        self.assertIn('apps/demo/feature.dart', [item['path'] for item in report['conflicts']])

    def test_unknown_or_legacy_provenance_is_not_silently_upgraded(self):
        metadata = self.write('blueprint.json', '{"schema":1}')
        report = upgrade_report(self.root, self.root)
        self.assertTrue(report['manualMigration'])
        self.assertEqual(metadata.read_text(), '{"schema":1}')
        metadata.write_text('{"schema":3}')
        with self.assertRaises(ValueError): upgrade_report(self.root, self.root)

    def test_artifact_manifest_covers_nested_resource_changes(self):
        bundle = self.root / 'bundle'
        self.write('bundle/bin/app', 'binary')
        resource = self.write('bundle/data/image.png', 'image1')
        first = describe_artifact(bundle, self.root)
        resource.write_text('image2')
        second = describe_artifact(bundle, self.root)
        self.assertNotEqual(first['treeSha256'], second['treeSha256'])
        with self.assertRaises(ValueError): describe_artifact(self.root / 'missing', self.root)
        with self.assertRaises(ValueError): verify_architecture(bundle, 'linux', 'x64')

    def test_generated_configuration_changes_source_identity(self):
        metadata = self.write('blueprint.json', '{"schema":2,"configuration":{"channel":"a"}}')
        first = source_manifest(self.root)['source_sha256']
        metadata.write_text('{"schema":2,"configuration":{"channel":"b"}}')
        self.assertNotEqual(source_manifest(self.root)['source_sha256'], first)

    def test_inherited_guides_change_source_identity_but_validation_logs_do_not(self):
        guide = self.write('docs/upgrade-guide.md', 'version 1')
        first = source_manifest(self.root)['source_sha256']
        guide.write_text('version 2')
        second = source_manifest(self.root)['source_sha256']
        self.assertNotEqual(first, second)
        self.write('docs/validation/result.log', 'local evidence')
        self.assertEqual(source_manifest(self.root)['source_sha256'], second)

    def test_export_without_git_has_content_identity(self):
        self.write('README.md', 'exported source')
        with patch('tool.blueprint_provenance.shutil.which', return_value=None):
            identity = source_identity(self.root)
        self.assertIsNone(identity['commit'])
        self.assertIsNone(identity['dirty'])
        self.assertEqual(identity['sourceSha256'], source_manifest(self.root)['source_sha256'])

    def test_generated_native_environment_is_not_source_but_native_project_is(self):
        self.write('apps/demo_app/android/local.properties', 'flutter.buildMode=debug')
        self.write('apps/demo_app/ios/Flutter/Generated.xcconfig', 'DART_DEFINES=old')
        before = source_manifest(self.root)['source_sha256']
        self.write('apps/demo_app/android/local.properties', 'flutter.buildMode=release')
        self.write('apps/demo_app/ios/Flutter/Generated.xcconfig', 'DART_DEFINES=new')
        self.assertEqual(source_manifest(self.root)['source_sha256'], before)
        self.write('apps/demo_app/ios/Runner.xcodeproj/project.pbxproj', 'native source')
        self.assertNotEqual(source_manifest(self.root)['source_sha256'], before)

    def test_gradle_project_cache_is_not_source_but_wrapper_is(self):
        self.write('apps/demo_app/android/.gradle/8.14/executionHistory/executionHistory.bin', 'cache-a')
        self.write('apps/demo_app/android/gradle/wrapper/gradle-wrapper.properties', 'distributionUrl=a')
        self.write('apps/demo_app/android/build.gradle.kts', 'plugins {}\n')
        before = source_manifest(self.root)
        self.write('apps/demo_app/android/.gradle/8.14/executionHistory/executionHistory.bin', 'cache-b')
        self.write('apps/demo_app/android/.gradle/buildLogic.lock', 'lock')
        after = source_manifest(self.root)
        self.assertEqual(after['source_sha256'], before['source_sha256'])
        self.assertFalse(any('.gradle' in name.split('/') for name in after['files']))
        self.write('apps/demo_app/android/gradle/wrapper/gradle-wrapper.properties', 'distributionUrl=b')
        wrapped = source_manifest(self.root)
        self.assertNotEqual(wrapped['source_sha256'], before['source_sha256'])
        self.assertIn('apps/demo_app/android/gradle/wrapper/gradle-wrapper.properties', wrapped['files'])
        self.write('apps/demo_app/android/build.gradle.kts', 'plugins { id("com.android.application") }\n')
        self.assertNotEqual(source_manifest(self.root)['source_sha256'], wrapped['source_sha256'])

    def test_install_is_idempotent_and_preserves_modified_owned_files(self):
        source = self.root / 'source'
        project = self.root / 'project'
        app = project / 'apps/demo_app'
        self.write('source/tool/capabilities/catalog.json', json.dumps({'schema': 1, 'capabilities': [
            {'id': 'demo', 'version': 1, 'platforms': ['web'], 'recipe': 'recipe'}]}))
        self.write('source/recipe/lib/features/demo/demo.dart', "const package = '__APP_PACKAGE__';\n")
        self.write('project/apps/demo_app/pubspec.yaml', 'name: demo_app\n')
        self.write('project/pubspec.yaml', 'name: demo\nworkspace:\n  - apps/demo_app\n')
        self.write('project/apps/demo_app/lib/core/capabilities/installed_capabilities.dart', 'const installedCapabilities = [];\n')
        self.write('project/blueprint.json', json.dumps({'schema': 2, 'template': 'minimal', 'app': 'apps/demo_app', 'platforms': ['web'], 'capabilities': {}}))
        plan = install_plan(project, app, ['demo'], source)
        FileTransaction(project, plan['changes']).commit()
        self.assertFalse(install_plan(project, app, ['demo'], source)['changes'])
        feature = app / 'lib/features/demo/demo.dart'
        self.assertIn('demo_app', feature.read_text())
        feature.write_text('user edit')
        with self.assertRaisesRegex(ValueError, 'conflicts'): install_plan(project, app, ['demo'], source)
        self.assertEqual(feature.read_text(), 'user edit')

    def test_install_merges_app_localizations_and_registers_optional_package(self):
        source = self.root / 'source'
        project = self.root / 'project'
        app = project / 'apps/demo_app'
        entry = {'id': 'demo', 'version': 1, 'platforms': ['web'],
                 'recipe': 'recipe', 'packages': ['koi_modules'],
                 'localizationSources': {locale: f'l10n/app_{locale}.arb'
                                         for locale in ('en', 'zh', 'zh_Hant')}}
        self.write('source/tool/capabilities/catalog.json', json.dumps({'schema': 1, 'capabilities': [entry]}))
        self.write('source/recipe/lib/features/demo.dart', 'const demo = true;\n')
        self.write('source/packages/koi_modules/pubspec.yaml', 'name: koi_modules\n')
        self.write('source/packages/koi_modules/lib/koi_modules.dart', 'class Module {}\n')
        for locale in ('en', 'zh', 'zh_Hant'):
            self.write(f'source/l10n/app_{locale}.arb', json.dumps({'@@locale': locale, 'demoTitle': f'Demo {locale}'}))
            self.write(f'project/apps/demo_app/lib/l10n/app_{locale}.arb', json.dumps({'@@locale': locale, 'ready': 'Ready'}))
        self.write('project/pubspec.yaml', 'name: demo\nworkspace:\n  - apps/demo_app\n')
        self.write('project/apps/demo_app/pubspec.yaml', 'name: demo_app\n')
        self.write('project/apps/demo_app/lib/core/capabilities/installed_capabilities.dart', 'const installedCapabilities = [];\n')
        self.write('project/blueprint.json', json.dumps({'schema': 2, 'template': 'minimal',
            'app': 'apps/demo_app', 'platforms': ['web'], 'capabilities': {}, 'managedFiles': {}}))
        english = source / 'l10n/app_en.arb'
        english.write_text(json.dumps({'@@locale': 'en', 'ready': 'Conflicting translation'}))
        with self.assertRaisesRegex(ValueError, 'Localization key conflicts'):
            install_plan(project, app, ['demo'], source)
        english.write_text(json.dumps({'@@locale': 'en', 'demoTitle': 'Demo en'}))
        plan = install_plan(project, app, ['demo'], source)
        self.assertIn('packages/koi_modules/lib/koi_modules.dart', plan['changes'])
        self.assertIn('  - packages/koi_modules', plan['changes']['pubspec.yaml'].decode())
        self.assertIn('koi_modules: any', plan['changes']['apps/demo_app/pubspec.yaml'].decode())
        self.assertEqual(json.loads(plan['changes']['apps/demo_app/lib/l10n/app_zh.arb'])['demoTitle'], 'Demo zh')
        FileTransaction(project, plan['changes']).commit()
        self.assertEqual(install_plan(project, app, ['demo'], source)['changes'], {})
        english.write_text(json.dumps({'@@locale': 'en', 'demoTitle': 'Updated Demo'}))
        updates = upgrade_report(project, source)['capabilityUpdates']
        self.assertEqual(updates[0]['id'], 'demo')
        self.assertIn('en localization changed', updates[0]['reasons'])


if __name__ == '__main__':
    unittest.main()
