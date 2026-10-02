import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';
import 'package:platform_lab/features/desktop_window/domain/window_port.dart';

class PluginWindowPort
    with WindowListener, ScreenListener
    implements WindowPort {
  bool _attached = false;
  VoidCallback? _onClose;
  VoidCallback? _onGeometry;
  @override
  Future<void> initialize({
    required VoidCallback onClose,
    required VoidCallback onGeometryChanged,
  }) async {
    if (kIsWeb ||
        !const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform)) {
      throw UnsupportedError(
        'Desktop window controls require macOS, Windows, or Linux',
      );
    }
    await windowManager.ensureInitialized();
    _attached = true;
    _onClose = onClose;
    _onGeometry = onGeometryChanged;
    windowManager.addListener(this);
    screenRetriever.addListener(this);
    // Do not replace titlebarStyle or AppKit toolbar: the host owns its chrome.
    await windowManager.setPreventClose(true);
    _normalBounds = await windowManager.getBounds();
  }

  Rect? _normalBounds;
  @override
  Future<List<WindowBounds>> workAreas() async => [
    for (final display in await screenRetriever.getAllDisplays())
      WindowBounds.fromLTWH(
        display.visiblePosition?.dx ?? 0,
        display.visiblePosition?.dy ?? 0,
        (display.visibleSize ?? display.size).width,
        (display.visibleSize ?? display.size).height,
      ),
  ];
  @override
  Future<WindowGeometry> geometry() async {
    final maximized = await windowManager.isMaximized();
    final current = await windowManager.getBounds();
    if (!maximized) _normalBounds = current;
    final bounds = maximized ? _normalBounds ?? current : current;
    return WindowGeometry(
      bounds: WindowBounds.fromLTWH(
        bounds.left,
        bounds.top,
        bounds.width,
        bounds.height,
      ),
      maximized: maximized,
    );
  }

  @override
  Future<void> applyGeometry(WindowGeometry geometry) async {
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    _normalBounds = Rect.fromLTWH(
      geometry.bounds.left,
      geometry.bounds.top,
      geometry.bounds.width,
      geometry.bounds.height,
    );
    await windowManager.setBounds(_normalBounds!);
    if (geometry.maximized) await windowManager.maximize();
  }

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();
  @override
  Future<void> setAlwaysOnTop(bool enabled) =>
      windowManager.setAlwaysOnTop(enabled);
  @override
  void onWindowClose() => _onClose?.call();
  @override
  void onWindowMoved() => _onGeometry?.call();
  @override
  void onWindowResized() => _onGeometry?.call();
  @override
  void onWindowMaximize() => _onGeometry?.call();
  @override
  void onWindowUnmaximize() => _onGeometry?.call();
  @override
  void onScreenEvent(String eventName) => unawaited(_recoverDisplay());
  Future<void> _recoverDisplay() async {
    try {
      await applyGeometry((await geometry()).fitTo(await workAreas()));
    } on PlatformException {
      /* A later geometry change retries persistence. */
    }
  }

  @override
  Future<void> close() async {
    if (!_attached) return;
    _attached = false;
    windowManager.removeListener(this);
    screenRetriever.removeListener(this);
    await windowManager.setPreventClose(false);
  }
}
