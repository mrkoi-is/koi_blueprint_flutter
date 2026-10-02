import 'dart:async';

/// Each attempt owns a fresh cancellation signal. Adapters wire onCancel to
/// their transport; dropping a stale response alone is not transport cancellation.
final class CatalogCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}
