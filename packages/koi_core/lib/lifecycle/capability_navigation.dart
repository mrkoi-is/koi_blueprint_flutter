import 'dart:async';

/// Early platform entry points can request a capability route before a host
/// router exists. The host decides whether the current session may navigate.
final class CapabilityNavigation {
  static final instance = CapabilityNavigation();
  final _pending = <String>[];
  Future<bool> Function(String)? _handler;
  bool _draining = false;
  int _generation = 0;

  void open(String capabilityId) {
    if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(capabilityId)) {
      throw ArgumentError.value(capabilityId);
    }
    if (!_pending.contains(capabilityId)) {
      if (_pending.length == 16) {
        _pending.removeAt(0);
      }
      _pending.add(capabilityId);
    }
    unawaited(retry());
  }

  void Function() attach(Future<bool> Function(String) handler) {
    final generation = ++_generation;
    _handler = handler;
    unawaited(retry());
    return () {
      if (generation == _generation) {
        _handler = null;
        ++_generation;
      }
    };
  }

  Future<void> retry() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_pending.isNotEmpty && _handler != null) {
        final generation = _generation;
        final id = _pending.first;
        bool accepted;
        try {
          accepted = await _handler!(id);
        } catch (_) {
          return;
        }
        if (generation != _generation) {
          continue;
        }
        if (!accepted) {
          return;
        }
        _pending.remove(id);
      }
    } finally {
      _draining = false;
    }
  }

  void clear() => _pending.clear();
}
