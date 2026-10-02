import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:platform_lab/features/desktop_window/data/window_geometry_store.dart';
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';

Future<WindowGeometryStore> open() async {
  final directory = await getApplicationSupportDirectory();
  return FileWindowGeometryStore(
    File('${directory.path}/window-geometry.json'),
  );
}

class FileWindowGeometryStore implements WindowGeometryStore {
  FileWindowGeometryStore(this.file);
  final File file;
  @override
  Future<WindowGeometry?> read() async {
    if (!await file.exists()) return null;
    try {
      return WindowGeometry.fromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(WindowGeometry geometry) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(geometry.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
