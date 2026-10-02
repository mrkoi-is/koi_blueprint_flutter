import 'dart:async';

import 'package:showcase_contracts/showcase_contracts.dart';
import 'package:koi_modules/koi_modules.dart';

/// The host owns this bus across all module switches.
final class HostShowcaseServices implements ShowcaseServices {
  final _refreshes = StreamController<void>.broadcast(sync: true);
  final List<String> _events = [];
  bool _closed = false;
  bool betaConfigured = true;
  CapabilityAvailability get betaAvailability => betaConfigured
      ? const CapabilityAvailability.available()
      : const CapabilityAvailability.unavailable('Beta 尚未配置，请启用后重试');

  bool get isClosed => _closed;
  List<String> get events => List.unmodifiable(_events);

  @override
  Stream<void> get refreshes => _refreshes.stream;

  @override
  void record(String event) {
    if (_closed) throw StateError('Shared infrastructure is closed.');
    _events.add(event);
  }

  void refresh() => _refreshes.add(null);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _refreshes.close();
  }
}
