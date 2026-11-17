import plistlib
import re
import tempfile
import unittest
from pathlib import Path

from tool.platform_localization import plan_apple_localizations


PROJECT = '''// !$*UTF8*$!
{
\tobjects = {
\t\t111111111111111111111111 /* Runner */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tpath = Runner;
\t\t};
\t\t222222222222222222222222 /* Runner */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildPhases = (
\t\t\t\t333333333333333333333333 /* Resources */,
\t\t\t);
\t\t};
\t\t333333333333333333333333 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tfiles = (
\t\t\t);
\t\t};
\t\t444444444444444444444444 /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\tfr,
\t\t\t);
\t\t};
\t};
}
'''


class AppleLocalizationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name)
        for platform in ('ios', 'macos'):
            runner = self.app / platform / 'Runner'
            runner.mkdir(parents=True)
            (runner / 'Info.plist').write_bytes(plistlib.dumps({'custom': 'keep', 'CFBundleLocalizations': ['fr']}))
            project = self.app / platform / 'Runner.xcodeproj/project.pbxproj'
            project.parent.mkdir()
            project.write_text(PROJECT)

    def apply(self, changes):
        for relative, data in changes.items():
            path = self.app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def test_base_languages_preserve_existing_resources_without_enabling_diagnostics(self):
        changes = plan_apple_localizations(self.app)
        for platform in ('ios', 'macos'):
            info = plistlib.loads(changes[f'{platform}/Runner/Info.plist'])
            self.assertEqual(info['CFBundleLocalizations'], ['fr', 'en', 'zh-Hans', 'zh-Hant'])
            self.assertEqual(info['custom'], 'keep')
            self.assertNotIn('NSLocalNetworkUsageDescription', info)
            project = changes[f'{platform}/Runner.xcodeproj/project.pbxproj'].decode()
            for locale in ('Base', 'fr', 'zh-Hans', 'zh-Hant'):
                self.assertIn(locale, project)
        self.apply(changes)
        self.assertEqual(plan_apple_localizations(self.app), changes)

    def test_permission_resources_are_linked_and_can_be_installed_after_creation(self):
        self.apply(plan_apple_localizations(self.app))
        changes = plan_apple_localizations(self.app, diagnostics=True)
        for platform in ('ios', 'macos'):
            project = changes[f'{platform}/Runner.xcodeproj/project.pbxproj'].decode()
            self.assertIn('isa = PBXVariantGroup', project)
            self.assertIn('isa = PBXBuildFile', project)
            self.assertEqual(project.count('/* InfoPlist.strings */,'), 2)
            for locale, text in [('en', 'View application'), ('zh-Hans', '局域网'), ('zh-Hant', '區域網路')]:
                resource = f'{locale}.lproj/InfoPlist.strings'
                self.assertIn(resource, project)
                self.assertIn(text, changes[f'{platform}/Runner/{resource}'].decode())
        self.apply(changes)
        self.assertEqual(plan_apple_localizations(self.app, diagnostics=True), changes)

    def test_pending_plist_changes_are_preserved(self):
        path = 'ios/Runner/Info.plist'
        pending = {path: plistlib.dumps({'UIBackgroundModes': ['audio']})}
        result = plan_apple_localizations(self.app, diagnostics=True, base_changes=pending)
        self.assertEqual(plistlib.loads(result[path])['UIBackgroundModes'], ['audio'])

    def test_edited_translations_or_detached_resources_fail_without_writes(self):
        changes = plan_apple_localizations(self.app, diagnostics=True)
        self.apply(changes)
        path = self.app / 'ios/Runner/zh-Hant.lproj/InfoPlist.strings'
        path.write_text('user translation')
        with self.assertRaisesRegex(ValueError, 'user changes'):
            plan_apple_localizations(self.app, diagnostics=True)
        self.assertEqual(path.read_text(), 'user translation')
        self.apply(changes)
        path = self.app / 'ios/Runner.xcodeproj/project.pbxproj'
        path.write_text(re.sub(r'^.* /\* InfoPlist.strings \*/,\n', '', path.read_text(), count=1, flags=re.M))
        with self.assertRaisesRegex(ValueError, 'Detached'):
            plan_apple_localizations(self.app, diagnostics=True)

    def test_xcode_serialization_keeps_resources_idempotent(self):
        self.apply(plan_apple_localizations(self.app, diagnostics=True))
        for platform in ('ios', 'macos'):
            path = self.app / platform / 'Runner.xcodeproj/project.pbxproj'
            text = re.sub(r'/\* Koi localized InfoPlist (?:begin|end) \*/\n', '', path.read_text())
            text = text.replace('/* InfoPlist.strings */', '/* InfoPlist.strings in Resources */')
            text = text.replace('name = "en";', 'name = en;').replace('path = "en.lproj/InfoPlist.strings";', 'path = en.lproj/InfoPlist.strings;')
            path.write_text(text)
        changes = plan_apple_localizations(self.app, diagnostics=True)
        for relative, content in changes.items():
            self.assertEqual((self.app / relative).read_bytes(), content)

    def test_non_apple_app_requires_no_native_files(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(plan_apple_localizations(Path(directory), diagnostics=True), {})

    def test_custom_permission_rationale_is_not_shadowed_by_stock_translations(self):
        path = self.app / 'ios/Runner/Info.plist'
        original = plistlib.dumps({'NSLocalNetworkUsageDescription': 'Custom product explanation'})
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, 'explicit localization merge'):
            plan_apple_localizations(self.app, diagnostics=True)
        self.assertEqual(path.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
