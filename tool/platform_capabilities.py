"""Plan bounded native runner additions for optional platform capabilities.

Returns app-relative bytes for the caller's compare-before-write transaction.
Never mutates the destination. Existing generated outputs must match exactly.
"""
from __future__ import annotations
import hashlib
import plistlib
import re
from pathlib import Path


def _once(source, anchor, replacement):
    if source.count(anchor) != 1:
        raise ValueError(f'Unsupported or edited native anchor: {anchor[:100]}')
    return source.replace(anchor, replacement, 1)


def _managed(source, marker, body, anchor):
    block = f'<!-- Koi {marker} begin -->\n{body}\n<!-- Koi {marker} end -->'
    if f'<!-- Koi {marker} begin -->' in source:
        if source.count(block) != 1:
            raise ValueError(f'Edited managed native configuration: {marker}')
        return source
    return _once(source, anchor, block + '\n' + anchor)


def plan_native_changes(app, selected_caps, config=None):
    app = Path(app)
    selected = set(selected_caps)
    config = config or {}
    output = {}

    windows_cmake = app / 'windows/CMakeLists.txt'
    if (app / 'windows').is_dir() and 'system-media' in selected:
        if not windows_cmake.is_file() or windows_cmake.is_symlink():
            raise ValueError('Missing or unsafe Windows CMake anchor')
        cmake = windows_cmake.read_text()
        original = 'cmake_minimum_required(VERSION 3.14)'
        managed = '# Koi platform audio CMake begin\ncmake_minimum_required(VERSION 3.15)\ncmake_policy(SET CMP0091 NEW)\n# Koi platform audio CMake end'
        if '# Koi platform audio CMake begin' in cmake:
            if cmake.count(managed) != 1 or cmake.count('cmake_policy(VERSION 3.15...3.25)') != 1:
                raise ValueError('Edited managed Windows audio CMake configuration')
        else:
            cmake = _once(cmake, original, managed)
            cmake = _once(cmake, 'cmake_policy(VERSION 3.14...3.25)', 'cmake_policy(VERSION 3.15...3.25)')
        output['windows/CMakeLists.txt'] = cmake.encode()

    def add(relative, content):
        value = content.encode() if isinstance(content, str) else content
        target = app / relative
        if target.is_symlink():
            raise ValueError(f'Refusing native symlink: {relative}')
        if target.exists() and target.read_bytes() != value:
            raise ValueError(f'Native output already exists with user changes: {relative}')
        output[relative] = value

    android = app / 'android/app/src/main'
    if android.is_dir() and selected & {'system-media', 'home-widget', 'network', 'lan'}:
        manifest_path = android / 'AndroidManifest.xml'
        manifest = manifest_path.read_text()
        if manifest.count('</application>') != 1 or manifest.count('</manifest>') != 1:
            raise ValueError('Unsupported Android manifest structure')
        if selected & {'network', 'lan', 'system-media'}:
            anchors = re.findall(r'<application\b[^>]*>', manifest)
            if len(anchors) != 1:
                raise ValueError('Unsupported Android application element')
            if 'android.permission.INTERNET' not in manifest:
                manifest = _managed(manifest, 'network permission', '<uses-permission android:name="android.permission.INTERNET" />', anchors[0])
            if 'lan' in selected and config.get('lan', {}).get('allowLocalHttp', False):
                if 'android:usesCleartextTraffic=' in anchors[0] and 'android:usesCleartextTraffic="true"' not in anchors[0]:
                    raise ValueError('Existing Android cleartext configuration requires explicit merge')
                if 'android:usesCleartextTraffic=' not in anchors[0]:
                    manifest = _once(manifest, anchors[0], anchors[0][:-1] + ' android:usesCleartextTraffic="true">')
        if 'system-media' in selected:
            if 'com.ryanheise.audioservice.AudioService' in manifest and '<!-- Koi system media begin -->' not in manifest:
                raise ValueError('Unmanaged AudioService manifest configuration')
            permissions = '\n'.join(f'<uses-permission android:name="android.permission.{name}" />' for name in ['WAKE_LOCK', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK'])
            # Permissions belong directly under manifest, before application.
            anchors = re.findall(r'<application\b[^>]*>', manifest)
            if len(anchors) != 1:
                raise ValueError('Unsupported Android application element')
            manifest = _managed(manifest, 'media permissions', permissions, anchors[0])
            components = '''<service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback" android:exported="true">
  <intent-filter><action android:name="android.media.browse.MediaBrowserService" /></intent-filter>
</service>
<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
  <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON" /></intent-filter>
</receiver>'''
            manifest = _managed(manifest, 'system media', components, '</application>')
            activities = list((android / 'kotlin').rglob('MainActivity.kt'))
            if len(activities) != 1:
                raise ValueError('Expected the pinned Flutter Kotlin MainActivity')
            activity = activities[0].read_text()
            if 'com.ryanheise.audioservice.AudioServiceActivity' not in activity:
                activity = _once(activity, 'import io.flutter.embedding.android.FlutterActivity', 'import com.ryanheise.audioservice.AudioServiceActivity')
                activity = _once(activity, 'MainActivity : FlutterActivity()', 'MainActivity : AudioServiceActivity()')
            elif 'MainActivity : AudioServiceActivity()' not in activity:
                raise ValueError('Edited AudioService MainActivity')
            output[activities[0].relative_to(app).as_posix()] = activity.encode()
        if 'home-widget' in selected:
            activities = list((android / 'kotlin').rglob('MainActivity.kt'))
            if len(activities) != 1:
                raise ValueError('Expected one Kotlin MainActivity for widget launch')
            match = re.search(r'^package ([a-zA-Z0-9_.]+)\s*$', activities[0].read_text(), re.M)
            if not match:
                raise ValueError('Missing Android package declaration')
            package = match.group(1)
            receiver = '''<receiver android:name=".KoiHomeWidgetProvider" android:exported="false">
  <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE" /></intent-filter>
  <meta-data android:name="android.appwidget.provider" android:resource="@xml/koi_home_widget_info" />
</receiver>'''
            manifest = _managed(manifest, 'home widget', receiver, '</application>')
            add(f'android/app/src/main/kotlin/{package.replace(".", "/")}/KoiHomeWidgetProvider.kt', _ANDROID_PROVIDER.replace('__PACKAGE__', package))
            add('android/app/src/main/res/layout/koi_home_widget.xml', _ANDROID_LAYOUT)
            add('android/app/src/main/res/xml/koi_home_widget_info.xml', _ANDROID_INFO)
        output[manifest_path.relative_to(app).as_posix()] = manifest.encode()

    ios = app / 'ios'
    if ios.is_dir() and selected & {'system-media', 'home-widget', 'lan'}:
        info_path = ios / 'Runner/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        if 'lan' in selected and config.get('lan', {}).get('allowLocalHttp', False):
            ats = info.setdefault('NSAppTransportSecurity', {})
            if not isinstance(ats, dict):
                raise ValueError('Unexpected App Transport Security format')
            if ats.get('NSAllowsArbitraryLoads', True) is not True:
                raise ValueError('Existing iOS HTTP restriction requires explicit merge')
            ats['NSAllowsArbitraryLoads'] = True
            ats['NSAllowsLocalNetworking'] = True
        if 'system-media' in selected:
            modes = info.setdefault('UIBackgroundModes', [])
            if not isinstance(modes, list):
                raise ValueError('Unexpected UIBackgroundModes format')
            if 'audio' not in modes:
                modes.append('audio')
        if 'home-widget' in selected:
            url_types = info.setdefault('CFBundleURLTypes', [])
            if not any('koi-workspace' in item.get('CFBundleURLSchemes', []) for item in url_types):
                url_types.append({'CFBundleURLName': 'KoiHomeWidget', 'CFBundleURLSchemes': ['koi-workspace']})
        output['ios/Runner/Info.plist'] = plistlib.dumps(info, sort_keys=False)
        if 'home-widget' in selected:
            project_path = ios / 'Runner.xcodeproj/project.pbxproj'
            project = project_path.read_text()
            identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9_.-]+);', project)
            bundle = next((value for value in identifiers if not value.endswith(('.RunnerTests', '.KoiHomeWidget'))), None)
            if not bundle:
                raise ValueError('Cannot determine Runner bundle identifier')
            options = config.get('home-widget', {})
            group = options.get('appGroup', f'group.{bundle}')
            if not re.fullmatch(r'group\.[A-Za-z0-9][A-Za-z0-9.-]+', group):
                raise ValueError('Invalid home-widget App Group')
            add('ios/KoiHomeWidget/KoiHomeWidget.swift', _IOS_WIDGET.replace('__APP_GROUP__', group))
            add('ios/KoiHomeWidget/Info.plist', plistlib.dumps({'CFBundleDisplayName': 'Workspace', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'XPC!', 'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1', 'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}, sort_keys=False))
            entitlements = {'com.apple.security.application-groups': [group]}
            add('ios/KoiHomeWidget/KoiHomeWidget.entitlements', plistlib.dumps(entitlements))
            runner_entitlements = ios / 'Runner/Runner.entitlements'
            current = plistlib.loads(runner_entitlements.read_bytes()) if runner_entitlements.exists() else {}
            groups = current.setdefault('com.apple.security.application-groups', [])
            if not isinstance(groups, list):
                raise ValueError('Unexpected application-groups entitlements')
            if group not in groups:
                groups.append(group)
            output['ios/Runner/Runner.entitlements'] = plistlib.dumps(current, sort_keys=False)
            output['ios/Runner.xcodeproj/project.pbxproj'] = _widget_project(project, bundle).encode()
            # The caller merges this into normal build defines; no Xcode signing
            # credentials or provisioning identities are inferred here.
            config_path = 'lib/features/home_widget/data/home_widget_configuration.dart'
            generated_config = f"// Generated from native App Group configuration.\nconst homeWidgetAppGroup = '{group}';\n".encode()
            existing_config = app / config_path
            default_config = b"// The capability installer replaces this default with its App Group.\nconst homeWidgetAppGroup = String.fromEnvironment('HOME_WIDGET_APP_GROUP');\n"
            if existing_config.exists() and existing_config.read_bytes() not in [default_config, generated_config]:
                raise ValueError('Edited native App Group Dart configuration')
            output[config_path] = generated_config
    macos = app / 'macos/Runner'
    if macos.is_dir() and selected & {'desktop-window', 'tray'}:
        delegate_path = macos / 'AppDelegate.swift'
        if not delegate_path.is_file() or delegate_path.is_symlink():
            raise ValueError('Missing or unsafe macOS AppDelegate anchor')
        delegate = delegate_path.read_text()
        original = '  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n    return true\n  }'
        managed = '  // Koi desktop close policy: Dart owns the cancellable save/exit protocol.\n  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n    return false\n  }'
        if managed not in delegate:
            delegate = _once(delegate, original, managed)
        reopen = _MACOS_REOPEN
        if 'applicationShouldHandleReopen' in delegate:
            if delegate.count(reopen) != 1:
                raise ValueError('Unmanaged macOS reopen handler requires an explicit merge')
        else:
            delegate = _once(delegate, '  override func applicationSupportsSecureRestorableState', reopen + '\n  override func applicationSupportsSecureRestorableState')
        output['macos/Runner/AppDelegate.swift'] = delegate.encode()
    if macos.is_dir() and selected & {'network', 'lan', 'system-media'}:
        for name in ['DebugProfile.entitlements', 'Release.entitlements']:
            path = macos / name
            if not path.is_file() or path.is_symlink():
                raise ValueError(f'Missing or unsafe macOS entitlement anchor: {name}')
            entitlements = plistlib.loads(path.read_bytes())
            required = ['com.apple.security.network.client']
            if 'lan' in selected:
                required.append('com.apple.security.network.server')
            if 'system-media' in selected:
                required.append('com.apple.security.files.user-selected.read-only')
            for key in required:
                if key in entitlements and entitlements[key] is not True:
                    raise ValueError(f'Conflicting macOS entitlement requires explicit merge: {key}')
                entitlements[key] = True
            output[f'macos/Runner/{name}'] = plistlib.dumps(entitlements, sort_keys=False)
    return output


def _widget_project(source, bundle):
    """Add a real WidgetKit target and embed dependency to a pinned PBX project."""
    ids = {name: hashlib.sha256(f'koi-widget:{bundle}:{name}'.encode()).hexdigest()[:24].upper() for name in ['group', 'swift', 'plist', 'entitlements', 'product', 'swiftBuild', 'embedBuild', 'sources', 'resources', 'frameworks', 'target', 'configList', 'debug', 'profile', 'release', 'embedPhase', 'dependency', 'proxy']}
    marker = '/* Koi WidgetKit target begin */'
    if marker in source:
        # Re-entry is accepted only if the managed block remains byte-identical.
        project_id = re.search(r'([A-F0-9]{24}) /\* Project object \*/ = \{', source)
        if not project_id:
            raise ValueError('Missing PBX project object')
        expected = _widget_objects(ids, bundle).replace('__PROJECT_ID__', project_id.group(1))
        if source.count(expected) != 1:
            raise ValueError('Edited managed WidgetKit target')
        return source
    if any(value in source for value in ids.values()):
        raise ValueError('WidgetKit object identifier collision')
    main_match = re.search(r'mainGroup = ([A-F0-9]{24});', source)
    products_match = re.search(r'productRefGroup = ([A-F0-9]{24}) /\* Products \*/;', source)
    runner_match = re.search(r'([A-F0-9]{24}) /\* Runner \*/ = \{\n\s*isa = PBXNativeTarget;', source)
    project_match = re.search(r'([A-F0-9]{24}) /\* Project object \*/ = \{', source)
    if not all([main_match, products_match, runner_match, project_match]):
        raise ValueError('Unsupported Flutter iOS project anchors')
    def in_object(text, identifier, field, addition):
        pattern = rf'(^\t\t{identifier}(?: /\*[^\n]*?\*/)? = \{{\n.*?\n\t\t\}};)'
        matches = list(re.finditer(pattern, text, re.S | re.M))
        if len(matches) != 1:
            raise ValueError(f'Ambiguous PBX object {identifier}')
        block = matches[0].group(1)
        anchor = f'{field} = (\n'
        block = _once(block, anchor, anchor + '\t\t\t\t' + addition + ',\n')
        return text[:matches[0].start()] + block + text[matches[0].end():]
    source = in_object(source, main_match.group(1), 'children', ids['group'] + ' /* KoiHomeWidget */')
    source = in_object(source, products_match.group(1), 'children', ids['product'] + ' /* KoiHomeWidget.appex */')
    source = in_object(source, runner_match.group(1), 'buildPhases', ids['embedPhase'] + ' /* Embed App Extensions */')
    source = in_object(source, runner_match.group(1), 'dependencies', ids['dependency'] + ' /* PBXTargetDependency */')
    source = in_object(source, project_match.group(1), 'targets', ids['target'] + ' /* KoiHomeWidget */')
    # Every Runner configuration with this bundle gets the App Group entitlement.
    pattern = rf'(PRODUCT_BUNDLE_IDENTIFIER = {re.escape(bundle)};)'
    if len(re.findall(pattern, source)) != 3:
        raise ValueError('Expected Debug/Profile/Release Runner bundle settings')
    if 'CODE_SIGN_ENTITLEMENTS' in source:
        raise ValueError('Unmanaged Runner entitlements settings require an explicit merge')
    source = re.sub(pattern, r'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\t\1', source)
    objects = _widget_objects(ids, bundle).replace('__PROJECT_ID__', project_match.group(1))
    return _once(source, '\tobjects = {', '\tobjects = {\n' + objects)


def _widget_objects(i, bundle):
    lines = ['/* Koi WidgetKit target begin */']
    def obj(key, kind, fields):
        lines.append(f'\t\t{i[key]} = {{isa = {kind}; {fields}}};')
    obj('swift', 'PBXFileReference', 'lastKnownFileType = sourcecode.swift; path = KoiHomeWidget.swift; sourceTree = "<group>";')
    obj('plist', 'PBXFileReference', 'lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
    obj('entitlements', 'PBXFileReference', 'lastKnownFileType = text.plist.entitlements; path = KoiHomeWidget.entitlements; sourceTree = "<group>";')
    obj('product', 'PBXFileReference', 'explicitFileType = "wrapper.app-extension"; path = KoiHomeWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('group', 'PBXGroup', f'children = ({i["swift"]}, {i["plist"]}, {i["entitlements"]}); path = KoiHomeWidget; sourceTree = "<group>";')
    obj('swiftBuild', 'PBXBuildFile', f'fileRef = {i["swift"]};')
    obj('embedBuild', 'PBXBuildFile', f'fileRef = {i["product"]}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy);}};')
    obj('sources', 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = ({i["swiftBuild"]}); runOnlyForDeploymentPostprocessing = 0;')
    obj('resources', 'PBXResourcesBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('frameworks', 'PBXFrameworksBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('embedPhase', 'PBXCopyFilesBuildPhase', f'buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({i["embedBuild"]}); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
    obj('proxy', 'PBXContainerItemProxy', f'containerPortal = __PROJECT_ID__; proxyType = 1; remoteGlobalIDString = {i["target"]}; remoteInfo = KoiHomeWidget;')
    obj('dependency', 'PBXTargetDependency', f'target = {i["target"]}; targetProxy = {i["proxy"]};')
    obj('target', 'PBXNativeTarget', f'buildConfigurationList = {i["configList"]}; buildPhases = ({i["sources"]}, {i["frameworks"]}, {i["resources"]}); buildRules = (); dependencies = (); name = KoiHomeWidget; productName = KoiHomeWidget; productReference = {i["product"]}; productType = "com.apple.product-type.app-extension";')
    for key, name in [('debug', 'Debug'), ('profile', 'Profile'), ('release', 'Release')]:
        obj(key, 'XCBuildConfiguration', f'buildSettings = {{APPLICATION_EXTENSION_API_ONLY = YES; CODE_SIGN_ENTITLEMENTS = KoiHomeWidget/KoiHomeWidget.entitlements; CODE_SIGN_STYLE = Automatic; INFOPLIST_FILE = KoiHomeWidget/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 14.0; PRODUCT_BUNDLE_IDENTIFIER = {bundle}.KoiHomeWidget; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SKIP_INSTALL = YES; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";}}; name = {name};')
    obj('configList', 'XCConfigurationList', f'buildConfigurations = ({i["debug"]}, {i["profile"]}, {i["release"]}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    lines.append('/* Koi WidgetKit target end */')
    return '\n'.join(lines)


_ANDROID_PROVIDER = '''package __PACKAGE__
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject

class KoiHomeWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
    val snapshot = runCatching { JSONObject(data.getString("koi_snapshot", "{}") ?: "{}") }.getOrNull()
    for (id in ids) {
      val views = RemoteViews(context.packageName, R.layout.koi_home_widget)
      val valid = snapshot?.optInt("version") == 1
      views.setTextViewText(R.id.koi_widget_title, if (valid) snapshot!!.optString("title") else "Workspace")
      views.setTextViewText(R.id.koi_widget_detail, if (valid) "${snapshot!!.optInt("completed")} · ${snapshot.optString("updatedAt")}" else "Open the app to publish a snapshot")
      views.setOnClickPendingIntent(R.id.koi_widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
      manager.updateAppWidget(id, views)
    }
  }
}
'''
_ANDROID_LAYOUT = '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android" android:id="@+id/koi_widget_root" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:padding="16dp" android:background="#F5F5F5">
<TextView android:id="@+id/koi_widget_title" android:layout_width="match_parent" android:layout_height="wrap_content" android:textColor="#202020" android:textSize="18sp" android:maxLines="2" />
<TextView android:id="@+id/koi_widget_detail" android:layout_width="match_parent" android:layout_height="wrap_content" android:textColor="#404040" android:textSize="13sp" android:maxLines="3" />
</LinearLayout>
'''
_ANDROID_INFO = '''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android" android:minWidth="180dp" android:minHeight="80dp" android:updatePeriodMillis="0" android:initialLayout="@layout/koi_home_widget" android:resizeMode="horizontal|vertical" android:widgetCategory="home_screen" />
'''
_IOS_WIDGET = '''import WidgetKit
import SwiftUI

struct KoiEntry: TimelineEntry {
  let date: Date
  let title: String
  let completed: Int
}
struct KoiProvider: TimelineProvider {
  func placeholder(in context: Context) -> KoiEntry { KoiEntry(date: Date(), title: "Workspace", completed: 0) }
  func getSnapshot(in context: Context, completion: @escaping (KoiEntry) -> Void) { completion(read()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<KoiEntry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .never))
  }
  private func read() -> KoiEntry {
    guard let value = UserDefaults(suiteName: "__APP_GROUP__")?.string(forKey: "koi_snapshot"),
          let data = value.data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          json["version"] as? Int == 1 else { return KoiEntry(date: Date(), title: "Open workspace", completed: 0) }
    return KoiEntry(date: Date(), title: json["title"] as? String ?? "Workspace", completed: json["completed"] as? Int ?? 0)
  }
}
struct KoiWidgetView: View {
  let entry: KoiEntry
  private var content: some View {
    VStack(alignment: .leading) { Text(entry.title).font(.headline); Text("\\(entry.completed)").font(.title) }
      .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .widgetURL(URL(string: "koi-workspace://home-widget"))
  }
  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) { Color(white: 0.96) }
    } else { content.background(Color(white: 0.96)) }
  }
}
@main
struct KoiHomeWidget: Widget {
  let kind = "KoiHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: KoiProvider()) { entry in KoiWidgetView(entry: entry) }
      .configurationDisplayName("Workspace").description("Latest workspace snapshot").supportedFamilies([.systemSmall, .systemMedium])
  }
}
'''


_MACOS_REOPEN = """  // Koi desktop reopen begin
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
    if !visible {
      for window in NSApp.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
  // Koi desktop reopen end
"""
