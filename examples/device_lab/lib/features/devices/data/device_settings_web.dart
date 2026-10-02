import 'dart:convert';

import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:web/web.dart' as web;

Future<DeviceSettingsStore> openDeviceSettings({
  String namespace = 'device_lab',
}) async {
  if (!RegExp(r'^[a-z_]{1,40}$').hasMatch(namespace)) {
    throw ArgumentError.value(namespace);
  }
  return WebDeviceSettings(key: 'koi_${namespace}_settings_v1');
}

final class WebDeviceSettings implements DeviceSettingsStore {
  WebDeviceSettings({this.key = 'koi_device_lab_settings_v1'});
  final String key;
  bool _closed = false;
  void _ensureOpen() {
    if (_closed) throw StateError('Settings store is closed');
  }

  @override
  Future<Map<String, Object?>> read() async {
    _ensureOpen();
    final value = web.window.localStorage.getItem(key);
    return value == null
        ? {}
        : Map<String, Object?>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    _ensureOpen();
    web.window.localStorage.setItem(key, jsonEncode(values));
  }

  @override
  Future<void> close() async => _closed = true;
}
