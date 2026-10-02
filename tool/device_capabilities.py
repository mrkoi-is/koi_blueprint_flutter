"""Pure incoming-intent runner wiring; callers apply the returned overlay atomically.

Pinned app_links 7.2.1 setup: https://github.com/llfbandit/app_links/tree/main/doc
This module neither registers protocols on this host nor starts network services.
"""
from __future__ import annotations
import plistlib
import re
from pathlib import Path


def _once(text, anchor, replacement):
    if text.count(anchor) != 1:
        raise ValueError(f'Unsupported incoming-intent runner anchor: {anchor[:80]}')
    return text.replace(anchor, replacement, 1)


def _block(text, marker, body, anchor, *, xml=False):
    begin, end = ((f'<!-- Koi {marker} begin -->', f'<!-- Koi {marker} end -->') if xml
                  else (f'// Koi {marker} begin', f'// Koi {marker} end'))
    block = f'{begin}\n{body}\n{end}'
    if begin in text:
        if text.count(block) != 1:
            raise ValueError(f'Edited managed incoming configuration: {marker}')
        return text
    return _once(text, anchor, block + '\n' + anchor)


def plan_device_changes(app, selected_caps, config=None, base_changes=None):
    """Return only changed/additional files, reading base_changes before disk.

    Config is keyed by capability ID. incoming-intents currently uses the fixed
    `koi` contract; arbitrary schemes need a matching Dart domain adapter.
    """
    if not set(selected_caps) & {'incoming-intents'}:
        return {}
    config = config or {}
    if config.get('incoming-intents', {}).get('scheme', 'koi') != 'koi':
        raise ValueError('The incoming intent adapter supports the koi scheme')
    app = Path(app)
    overlay = base_changes or {}
    result = {}

    def read(relative):
        target = app / relative
        if target.is_symlink():
            raise ValueError(f'Refusing incoming runner symlink: {relative}')
        return overlay.get(relative, target.read_bytes() if target.exists() else None)

    def add(relative, value):
        content = value.encode() if isinstance(value, str) else value
        previous = read(relative)
        if previous is not None and previous != content:
            raise ValueError(f'Edited incoming generated asset: {relative}')
        result[relative] = content

    for platform in ('macos', 'ios'):
        relative = f'{platform}/Runner/Info.plist'
        raw = read(relative)
        if raw is None:
            continue
        info = plistlib.loads(raw)
        entries = info.setdefault('CFBundleURLTypes', [])
        if not isinstance(entries, list):
            raise ValueError('CFBundleURLTypes must be an array')
        desired = {'CFBundleURLName': 'KoiIncomingIntents', 'CFBundleURLSchemes': ['koi']}
        ours = [item for item in entries if item.get('CFBundleURLName') == 'KoiIncomingIntents']
        if ours and ours != [desired]:
            raise ValueError('Edited Koi incoming URL registration')
        if not ours:
            if any('koi' in item.get('CFBundleURLSchemes', []) for item in entries):
                raise ValueError('Unmanaged koi scheme registration')
            entries.append(desired)
        # App links owns URL delivery; Flutter routing must not consume it first.
        info['FlutterDeepLinkingEnabled'] = False
        if platform == 'ios':
            info['LSSupportsOpeningDocumentsInPlace'] = True
        docs = info.setdefault('CFBundleDocumentTypes', [])
        document_type = {'CFBundleTypeName': 'Koi text import', 'CFBundleTypeRole': 'Viewer',
                         'LSHandlerRank': 'Alternate', 'LSItemContentTypes': ['public.plain-text']}
        named = [item for item in docs if item.get('CFBundleTypeName') == 'Koi text import']
        if named and named != [document_type]:
            raise ValueError('Edited incoming document registration')
        if not named:
            docs.append(document_type)
        result[relative] = plistlib.dumps(info, sort_keys=False)
        if platform == 'macos':
            delegate_path = 'macos/Runner/AppDelegate.swift'
            delegate_raw = read(delegate_path)
            if delegate_raw is not None:
                delegate = delegate_raw.decode()
                if 'import app_links' not in delegate:
                    delegate = _once(delegate, 'import FlutterMacOS', 'import FlutterMacOS\nimport app_links')
                if '// Koi incoming documents begin' in delegate:
                    if delegate.count(_MACOS_DOCUMENTS) != 1:
                        raise ValueError('Edited macOS document callback')
                else:
                    anchor = 'class AppDelegate: FlutterAppDelegate {'
                    delegate = _once(delegate, anchor, anchor + '\n' + _MACOS_DOCUMENTS)
                result[delegate_path] = delegate.encode()


    relative = 'android/app/src/main/AndroidManifest.xml'
    raw = read(relative)
    if raw is not None:
        manifest = raw.decode()
        activities = list(re.finditer(r'<activity\b[^>]*android:name="(?:\.MainActivity|[A-Za-z0-9_.]+\.MainActivity)"[^>]*>', manifest, re.S))
        if len(activities) != 1:
            raise ValueError('Expected one MainActivity for incoming intents')
        anchor = activities[0].group()
        body = '''<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="koi" />
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:scheme="content" android:mimeType="text/plain" />
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.SEND" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:mimeType="text/plain" />
</intent-filter>'''
        # Keep the bounded custom scheme filter separate from launcher filters.
        if '<!-- Koi incoming intents begin -->' not in manifest and 'flutter_deeplinking_enabled' in manifest:
            raise ValueError('Unmanaged Flutter deep-link configuration')
        sentinel = '<!-- Koi incoming activity anchor -->'
        if sentinel not in manifest:
            manifest = _once(manifest, anchor, anchor + '\n' + sentinel)
        manifest = _block(manifest, 'incoming intents', body, sentinel, xml=True)
        result[relative] = manifest.encode()
        activities = list((app / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
        if len(activities) != 1:
            raise ValueError('Expected one Kotlin MainActivity for content ingress')
        activity_path = activities[0].relative_to(app).as_posix()
        activity = read(activity_path).decode()
        match = re.search(r'class MainActivity : ([A-Za-z0-9_]+)\(\)(?: \{\s*\})?\s*$', activity)
        marker = '// Koi incoming file adapter begin'
        if marker in activity:
            if activity.count(_ANDROID_ADAPTER) != 1:
                raise ValueError('Edited incoming Kotlin adapter')
        elif match:
            activity = activity[:match.start()] + f'class MainActivity : {match.group(1)}() {{\n' + _ANDROID_ADAPTER + '\n}\n'
        else:
            raise ValueError('MainActivity has custom lifecycle code; merge incoming adapter explicitly')
        result[activity_path] = activity.encode()


    relative = 'windows/runner/main.cpp'
    raw = read(relative)
    if raw is not None:
        source = raw.decode()
        header = '#include "app_links/app_links_plugin_c_api.h"'
        if header not in source:
            source = _once(source, '#include "utils.h"', '#include "utils.h"\n' + header)
        anchor = '  // Attach to console'
        matches = [m.start() for m in re.finditer(re.escape(anchor), source)]
        if len(matches) != 1:
            raise ValueError('Missing pinned Windows startup anchor')
        source = _block(source, 'incoming forwarding', '  if (SendAppLinkToInstance()) {\n    return EXIT_SUCCESS;\n  }', anchor)
        result[relative] = source.encode()
        # An explicit local installer command, never executed by capability install.
        add('windows/register_koi_protocol.ps1', _WINDOWS_REGISTRATION)

    relative = next((name for name in ('linux/runner/my_application.cc', 'linux/my_application.cc') if read(name) is not None), None)
    if relative:
        source = read(relative).decode()
        anchor = '  GtkWindow* window ='
        body = '''  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }'''
        source = _block(source, 'incoming activation', body, anchor)
        source = source.replace('G_APPLICATION_NON_UNIQUE', 'G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN')
        if 'G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN' not in source:
            raise ValueError('Missing Linux command-line application flags')
        start = source.index('static gboolean my_application_local_command_line')
        end = source.index('// Implements GObject::dispose.', start)
        section = source[start:end]
        old = '*exit_status = 0;\n\n  return TRUE;'
        new = '*exit_status = 0;\n\n  return FALSE;'
        if new not in section:
            section = _once(section, old, new)
        source = source[:start] + section + source[end:]
        result[relative] = source.encode()
        add('linux/register_koi_protocol.sh', _LINUX_REGISTRATION)
    return result


_WINDOWS_REGISTRATION = r'''param([Parameter(Mandatory=$true)][string]$Executable)
# Run explicitly for a built local executable. Uses the current user's registry.
$resolved = (Resolve-Path -LiteralPath $Executable -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($resolved) -ne '.exe') { throw 'Expected an executable' }
$key = 'HKCU:\Software\Classes\koi'
if (Test-Path -LiteralPath $key) {
  $existing = (Get-ItemProperty -LiteralPath "$key\shell\open\command" -ErrorAction Stop).'(default)'
  if ($existing -ne ('"' + $resolved + '" "%1"')) { throw 'koi is already registered to another executable' }
}
New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty -LiteralPath $key -Name 'URL Protocol' -Value ''
Set-ItemProperty -LiteralPath "$key\shell\open\command" -Name '(default)' -Value ('"' + $resolved + '" "%1"')
'''
_LINUX_REGISTRATION = r'''#!/usr/bin/env sh
set -eu
# Pass the absolute path to the built executable; no root privileges are needed.
exe=${1:?Pass the absolute executable path}
case "$exe" in /*) ;; *) echo 'Absolute path required' >&2; exit 2;; esac
[ -x "$exe" ] || { echo 'Executable not found' >&2; exit 2; }
case "$exe" in *'"'*|*'%'*|*'`'*|*'$'*) echo 'Unsupported desktop Exec path' >&2; exit 2;; esac
appdir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$appdir"
file="$appdir/koi-incoming.desktop"
if [ -e "$file" ]; then echo 'Existing registration retained; inspect it before replacing' >&2; exit 2; fi
printf '[Desktop Entry]\nType=Application\nName=Koi Incoming\nExec="%s" %%u\nTerminal=false\nMimeType=x-scheme-handler/koi;\n' "$exe" > "$file"
xdg-mime default koi-incoming.desktop x-scheme-handler/koi
'''


_ANDROID_ADAPTER = r'''// Koi incoming file adapter begin
  private fun normalizeIncoming(source: android.content.Intent?): android.content.Intent? {
    if (source == null || source.action != android.content.Intent.ACTION_SEND) return source
    val uri = source.getParcelableExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)
    if (uri != null) return android.content.Intent(source).setAction(android.content.Intent.ACTION_VIEW).setData(uri)
    val text = source.getCharSequenceExtra(android.content.Intent.EXTRA_TEXT)?.toString() ?: return source
    val bytes = text.toByteArray(Charsets.UTF_8)
    if (bytes.size > 256 * 1024) return source
    val file = java.io.File.createTempFile("incoming-", ".txt", cacheDir)
    file.writeBytes(bytes)
    return android.content.Intent(source).setAction(android.content.Intent.ACTION_VIEW).setData(android.net.Uri.fromFile(file))
  }
  override fun onCreate(state: android.os.Bundle?) {
    intent = normalizeIncoming(intent)
    super.onCreate(state)
  }
  override fun onNewIntent(source: android.content.Intent) {
    val normalized = normalizeIncoming(source) ?: source
    intent = normalized
    super.onNewIntent(normalized)
  }
  override fun configureFlutterEngine(engine: io.flutter.embedding.engine.FlutterEngine) {
    super.configureFlutterEngine(engine)
    io.flutter.plugin.common.MethodChannel(engine.dartExecutor.binaryMessenger, "koi_blueprint/incoming_files")
      .setMethodCallHandler { call, result ->
        if (call.method != "readContent") { result.notImplemented(); return@setMethodCallHandler }
        val value = call.argument<String>("uri")
        val uri = value?.let { android.net.Uri.parse(it) }
        if (uri?.scheme != "content") { result.error("invalid_uri", "Expected content URI", null); return@setMethodCallHandler }
        Thread {
          try {
            val name = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
              if (it.moveToFirst()) it.getString(0) else "import.txt"
            } ?: "import.txt"
            val data = contentResolver.openInputStream(uri)?.use { input ->
              val buffer = ByteArray(8192)
              val output = java.io.ByteArrayOutputStream()
              while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > 256 * 1024) throw IllegalArgumentException("Text file exceeds 256 KiB")
                output.write(buffer, 0, count)
              }
              output.toByteArray()
            } ?: throw IllegalArgumentException("Content provider did not open file")
            runOnUiThread { result.success(mapOf("name" to name, "bytes" to data)) }
          } catch (error: Exception) {
            runOnUiThread { result.error("content_read_failed", error.message, null) }
          }
        }.start()
      }
  }
// Koi incoming file adapter end'''


_MACOS_DOCUMENTS = r'''// Koi incoming documents begin
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames.prefix(64) {
      let source = URL(fileURLWithPath: filename)
      let scoped = source.startAccessingSecurityScopedResource()
      defer { if scoped { source.stopAccessingSecurityScopedResource() } }
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: filename)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 256 * 1024 else { continue }
        let data = try Data(contentsOf: source)
        guard data.count <= 256 * 1024 else { continue }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("koi-incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try data.write(to: destination, options: .atomic)
        AppLinks.shared.handleLink(link: destination.absoluteString)
      } catch {
        // The Dart importer surfaces unreadable paths without overwriting a draft.
        AppLinks.shared.handleLink(link: source.absoluteString)
      }
    }
    sender.reply(toOpenOrPrint: .success)
  }
// Koi incoming documents end'''
