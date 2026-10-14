import 'package:platform_lab/features/desktop_window/data/window_geometry_store_stub.dart'
    if (dart.library.io) 'package:platform_lab/features/desktop_window/data/window_geometry_store_native.dart'
    as platform;
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';

abstract interface class WindowGeometryStore {
  Future<WindowGeometry?> read();
  Future<void> write(WindowGeometry geometry);
}

Future<WindowGeometryStore> openWindowGeometryStore() => platform.open();
