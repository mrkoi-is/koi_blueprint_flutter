import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:workbench_app/features/workspace/data/native_directory_index_source.dart';
import 'package:workbench_app/features/workspace/domain/directory_selection.dart';

DirectoryIndexPicker createDirectoryIndexPicker() => _NativePicker();

final class _NativePicker implements DirectoryIndexPicker {
  @override
  Future<DirectorySelection?> pick() async {
    final path = await getDirectoryPath();
    if (path == null) return null;
    return DirectorySelection(
      label:
          path
              .split(Platform.pathSeparator)
              .where((part) => part.isNotEmpty)
              .lastOrNull ??
          path,
      identity: path,
      source: NativeDirectoryIndexSource(path),
    );
  }
}
