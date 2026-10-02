import 'dart:async';
import 'dart:collection';

import 'package:device_lab/features/devices/domain/device_contracts.dart';

/// Readiness, deduplication and draft protection are independent of native plugins.
final class IncomingIntentCoordinator {
  IncomingIntentCoordinator({
    required this.dispatch,
    required this.canNavigate,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final Future<void> Function(IncomingIntent) dispatch;
  final Future<bool> Function() canNavigate;
  final DateTime Function() _clock;
  final _queue = Queue<IncomingIntent>();
  final _seen = <String, DateTime>{};
  Future<void> _pending = Future.value();
  int _activeDrains = 0;
  bool _ready = false;
  bool _closed = false;
  int get pendingCount => _queue.length;

  Future<IncomingResult> receive(IncomingIntent intent) async {
    if (_closed) throw StateError('Incoming intents are closed');
    final now = _clock();
    _seen.removeWhere(
      (_, time) => now.difference(time) >= const Duration(seconds: 2),
    );
    if (_seen.containsKey(intent.id) ||
        _queue.any((item) => item.id == intent.id)) {
      return IncomingResult.duplicate;
    }
    if (_queue.length >= 64) {
      throw StateError('Too many pending incoming events');
    }
    _seen[intent.id] = now;
    if (_seen.length > 256) _seen.remove(_seen.keys.first);
    _queue.add(intent);
    if (!_ready) return IncomingResult.queued;
    await drain();
    return _queue.contains(intent)
        ? IncomingResult.blocked
        : IncomingResult.accepted;
  }

  Future<void> markReady() {
    _ready = true;
    return drain();
  }

  Future<void> drain() {
    _activeDrains++;
    final next = _pending
        .then((_) async {
          while (_ready && !_closed && _queue.isNotEmpty) {
            if (!await canNavigate() || _closed) return;
            final intent = _queue.first;
            await dispatch(intent);
            if (_queue.isNotEmpty && identical(_queue.first, intent)) {
              _queue.removeFirst();
            }
          }
        })
        .whenComplete(() => _activeDrains--);
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void clearPending() => _queue.clear();
  Future<void> close() async {
    _closed = true;
    _ready = false;
    if (_activeDrains > 0) await _pending;
    _queue.clear();
    _seen.clear();
  }
}
