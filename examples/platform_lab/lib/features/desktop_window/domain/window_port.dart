import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';

/// Platform mechanics only. AppKit toolbar ownership stays with the host App.
abstract interface class WindowPort {
  Future<void> initialize({
    required void Function() onClose,
    required void Function() onGeometryChanged,
  });
  Future<List<WindowBounds>> workAreas();
  Future<WindowGeometry> geometry();
  Future<void> applyGeometry(WindowGeometry geometry);
  Future<void> show();
  Future<void> hide();
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> close();
}
