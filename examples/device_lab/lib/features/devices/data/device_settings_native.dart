import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:path_provider/path_provider.dart';

Future<DeviceSettingsStore> openDeviceSettings({
  String namespace = 'device_lab',
}) async {
  if (!RegExp(r'^[a-z_]{1,40}$').hasMatch(namespace)) {
    throw ArgumentError.value(namespace);
  }
  final support = await getApplicationSupportDirectory();
  return NativeDeviceSettings(File('${support.path}/$namespace/settings.json'));
}

final class NativeDeviceSettings implements DeviceSettingsStore {
  NativeDeviceSettings(this.file);
  final File file;
  Future<void> _pending = Future.value();
  bool _closed = false;
  Future<T> _serialize<T>(Future<T> Function() action) {
    if (_closed) throw StateError('Settings store is closed');
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<Map<String, Object?>> read() => _serialize(() async {
    final backup = File('${file.path}.backup');
    try {
      if (await file.exists()) {
        return Map<String, Object?>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      }
    } catch (_) {
      if (!await backup.exists()) rethrow;
    }
    if (await backup.exists()) {
      return Map<String, Object?>.from(
        jsonDecode(await backup.readAsString()) as Map,
      );
    }
    return {};
  });
  @override
  Future<void> write(Map<String, Object?> values) {
    final encoded = jsonEncode(values);
    return _serialize(() async {
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.pending');
      final backup = File('${file.path}.backup');
      await pending.writeAsString(encoded, flush: true);
      var moved = false;
      if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
        moved = true;
      }
      try {
        await pending.rename(file.path);
      } catch (_) {
        if (moved && !await file.exists()) await backup.rename(file.path);
        rethrow;
      }
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _pending;
  }
}
