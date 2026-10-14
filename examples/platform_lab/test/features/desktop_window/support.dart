import 'package:platform_lab/features/desktop_window/domain/window_port.dart';
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';
import 'package:platform_lab/features/desktop_window/data/window_geometry_store.dart';

class FakeGeometryStore implements WindowGeometryStore {
  WindowGeometry? value;
  bool fail = false;
  @override
  Future<WindowGeometry?> read() async => value;
  @override
  Future<void> write(WindowGeometry geometry) async {
    if (fail) throw StateError('disk full');
    value = geometry;
  }
}

class FakeWindow implements WindowPort {
  WindowGeometry current = const WindowGeometry(
    bounds: WindowBounds.fromLTWH(100, 100, 1000, 700),
  );
  bool hidden = false;
  bool onTop = false;
  bool closed = false;
  bool failMini = false;
  void Function()? geometryChanged;
  @override
  Future<void> initialize({
    required void Function() onClose,
    required void Function() onGeometryChanged,
  }) async {
    geometryChanged = onGeometryChanged;
  }

  @override
  Future<List<WindowBounds>> workAreas() async => [
    const WindowBounds.fromLTWH(0, 20, 1440, 880),
  ];
  @override
  Future<WindowGeometry> geometry() async => current;
  @override
  Future<void> applyGeometry(WindowGeometry geometry) async {
    current = geometry;
  }

  @override
  Future<void> show() async {
    hidden = false;
  }

  @override
  Future<void> hide() async {
    hidden = true;
  }

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    if (failMini && value) throw StateError('window refused');
    onTop = value;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
