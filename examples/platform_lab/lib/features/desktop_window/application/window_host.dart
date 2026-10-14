import 'package:platform_lab/features/desktop_window/domain/window_port.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:platform_lab/features/desktop_window/data/window_geometry_store.dart';
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';

/// One native resource owner; presentation observes it without owning the window.
class DesktopWindowHost extends ChangeNotifier {
  DesktopWindowHost({
    required this.port,
    required this.store,
    required this.requestExit,
  });
  final WindowPort port;
  final WindowGeometryStore store;
  final Future<bool> Function() requestExit;
  bool ready = false;
  bool trayAvailable = false;
  bool hideOnClose = false;
  bool mini = false;
  bool _closed = false;
  bool _requestingClose = false;
  WindowGeometry? _normal;
  Future<void>? _modeQueue;
  Timer? _debounce;
  Future<void>? _pending;
  String? error;

  Future<void> initialize() async {
    try {
      await port.initialize(
        onClose: () => unawaited(closeRequested()),
        onGeometryChanged: _geometryChanged,
      );
      final restored = await store.read();
      if (restored != null) {
        await port.applyGeometry(restored.fitTo(await port.workAreas()));
      }
      ready = true;
      notifyListeners();
    } catch (failure) {
      error = '$failure';
      try {
        await port.close();
      } catch (_) {}
      notifyListeners();
    }
  }

  void _geometryChanged() {
    if (_closed || mini) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(saveGeometry()),
    );
  }

  Future<void> saveGeometry() {
    _pending = (_pending ?? Future<void>.value()).then((_) async {
      if (_closed || mini) return;
      try {
        await store.write(await port.geometry());
        error = null;
      } catch (failure) {
        error = '$failure';
      }
      if (!_closed) notifyListeners();
    });
    return _pending!;
  }

  void configureTray({required bool available, required bool closeToTray}) {
    trayAvailable = available;
    hideOnClose = available && closeToTray;
    notifyListeners();
  }

  Future<void> closeRequested() async {
    if (_closed || _requestingClose) return;
    _requestingClose = true;
    try {
      if (hideOnClose && trayAvailable) {
        await port.hide();
      } else {
        await saveGeometry();
        if (!await requestExit()) await port.show();
      }
    } catch (failure) {
      error = '$failure';
      await port.show();
      notifyListeners();
    } finally {
      _requestingClose = false;
    }
  }

  Future<void> show() => port.show();
  Future<void> quit() async {
    if (!ready || _closed) return;
    await saveGeometry();
    if (!await requestExit()) await port.show();
  }

  Future<void> setMini(bool enabled) {
    _modeQueue = (_modeQueue ?? Future<void>.value()).then(
      (_) => _applyMini(enabled),
    );
    return _modeQueue!;
  }

  Future<void> _applyMini(bool enabled) async {
    if (_closed || !ready || mini == enabled) return;
    try {
      if (enabled) {
        _normal = await port.geometry();
        mini = true;
        final bounds = _normal!.bounds;
        await port.applyGeometry(
          WindowGeometry(
            bounds: WindowBounds.fromLTWH(bounds.left, bounds.top, 380, 280),
          ).fitTo(await port.workAreas()),
        );
        await port.setAlwaysOnTop(true);
      } else {
        await port.setAlwaysOnTop(false);
        if (_normal != null) {
          await port.applyGeometry(_normal!.fitTo(await port.workAreas()));
        }
        mini = false;
      }
      error = null;
    } catch (failure) {
      error = '$failure';
      try {
        await port.setAlwaysOnTop(false);
        if (_normal != null) {
          await port.applyGeometry(_normal!.fitTo(await port.workAreas()));
        }
      } catch (_) {
        /* Preserve the original failure for retry. */
      }
      mini = false;
    }
    notifyListeners();
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _debounce?.cancel();
    if (_modeQueue != null) await _modeQueue;
    if (mini) await setMini(false);
    if (ready) await saveGeometry();
    _closed = true;
    await port.close();
    super.dispose();
  }
}
