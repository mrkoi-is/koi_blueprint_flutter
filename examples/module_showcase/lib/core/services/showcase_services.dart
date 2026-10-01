import 'dart:async';

import 'package:showcase_contracts/showcase_contracts.dart';

/// The host owns this bus across all module switches.
final class HostShowcaseServices implements ShowcaseServices {
  final _refreshes = StreamController<void>.broadcast(sync: true);
  final List<String> _events = [];
  bool _closed = false;

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
