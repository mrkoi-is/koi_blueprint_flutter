import 'dart:typed_data';

/// A cache is disposable derived data, never the user's asset store. Keys carry
/// source, adapter version and session scope; clear only affects this owner.
final class ResponseCache {
  ResponseCache({
    this.maxBytes = 2 * 1024 * 1024,
    this.maxEntries = 128,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (maxBytes < 1 || maxEntries < 1 || ttl <= Duration.zero) {
      throw ArgumentError('Invalid cache limits');
    }
  }
  final int maxBytes, maxEntries;
  final Duration ttl;
  final DateTime Function() _now;
  final _entries = <String, ({Uint8List bytes, DateTime expires})>{};
  int _size = 0;
  int get sizeBytes => _size;
  int get count => _entries.length;
  Uint8List? get(String key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _size -= value.bytes.length;
    if (!_now().isBefore(value.expires)) return null;
    _entries[key] = value;
    _size += value.bytes.length;
    return Uint8List.fromList(value.bytes);
  }

  void put(String key, List<int> bytes) {
    remove(key);
    if (bytes.length > maxBytes) return;
    while (_entries.isNotEmpty &&
        (_size + bytes.length > maxBytes || _entries.length >= maxEntries)) {
      remove(_entries.keys.first);
    }
    _entries[key] = (
      bytes: Uint8List.fromList(bytes),
      expires: _now().add(ttl),
    );
    _size += bytes.length;
  }

  void remove(String key) {
    final old = _entries.remove(key);
    if (old != null) _size -= old.bytes.length;
  }

  void clear() {
    _entries.clear();
    _size = 0;
  }
}
