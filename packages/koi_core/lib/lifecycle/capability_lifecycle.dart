import 'dart:async';

/// Composition owners register their resources with the host exit coordinator.
/// Preparation must remain reversible; only [close] releases live resources.
final class CapabilityLifecycle {
  static final instance = CapabilityLifecycle();
  final _owners =
      <
        Object,
        ({Future<bool> Function() prepare, Future<void> Function() close})
      >{};
  Future<void>? _closing;

  void Function() register({
    required Future<bool> Function() prepare,
    required Future<void> Function() close,
  }) {
    if (_closing != null) throw StateError('Capabilities are closing');
    final key = Object();
    _owners[key] = (prepare: prepare, close: close);
    return () => _owners.remove(key);
  }

  Future<bool> prepare() async {
    for (final entry in _owners.entries.toList().reversed) {
      if (_owners.containsKey(entry.key) && !await entry.value.prepare()) {
        return false;
      }
    }
    return true;
  }

  Future<void> close() =>
      _closing ??= Future<void>.sync(_close)
          .whenComplete(() => _closing = null);
  Future<void> _close() async {
    final failures = <Object>[];
    while (_owners.isNotEmpty) {
      final key = _owners.keys.last;
      final owner = _owners.remove(key)!;
      try {
        await owner.close();
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('Capability cleanup failed: $failures');
    }
  }
}
