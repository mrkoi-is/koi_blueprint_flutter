import 'dart:async';
import 'dart:convert';

import 'package:device_lab/features/devices/domain/device_contracts.dart';

final class MemorySettings implements DeviceSettingsStore {
  Map<String, Object?> values = {};
  bool fail = false;
  bool closed = false;
  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(values)) as Map);
  @override
  Future<void> write(Map<String, Object?> next) async {
    if (fail) throw StateError('disk full');
    values = Map<String, Object?>.from(jsonDecode(jsonEncode(next)) as Map);
  }

  @override
  Future<void> close() async => closed = true;
}

final class FakeDiscovery implements DeviceDiscovery {
  final events = StreamController<List<DiscoveredDevice>>.broadcast();
  int starts = 0;
  @override
  Stream<List<DiscoveredDevice>> get changes => events.stream;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> close() => events.close();
}

final class FakeLinks implements IncomingLinkSource {
  final events = StreamController<Uri>.broadcast();
  Uri? initialUri;
  @override
  Stream<Uri> get links => events.stream;
  @override
  Future<Uri?> initial() async => initialUri;
}
