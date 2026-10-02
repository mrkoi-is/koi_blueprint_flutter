import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:workbench_app/core/preferences/ui_preferences_store.dart';

Future<UiPreferencesStore> open() async {
  final directory = await getApplicationSupportDirectory();
  return FileUiPreferencesStore(File('${directory.path}/ui-preferences.json'));
}

final class FileUiPreferencesStore implements UiPreferencesStore {
  FileUiPreferencesStore(this.file);
  final File file;
  Future<void> _pending = Future.value();
  bool _closed = false;

  @override
  Future<Map<String, Object?>> read() async {
    await _pending;
    if (_closed) throw StateError('Preferences are closed');
    if (!await file.exists()) return {};
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (decoded['schema'] != 1) {
      throw const FormatException('Unknown preferences schema');
    }
    return Map<String, Object?>.from(decoded['values'] as Map);
  }

  @override
  Future<void> write(Map<String, Object?> values) {
    if (_closed) return Future.error(StateError('Preferences are closed'));
    final bytes = utf8.encode(jsonEncode({'schema': 1, 'values': values}));
    final operation = _pending.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.pending');
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _pending;
  }
}
