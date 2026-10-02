import 'dart:async';

final class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => 'Request cancelled';
}

final class Cancellation {
  final _listeners = <void Function()>{};
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const RequestCancelled();
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

final class HttpPayload {
  HttpPayload({
    required this.status,
    required Map<String, String> headers,
    required this.body,
  }) : headers = Map.unmodifiable(
         headers.map((key, value) => MapEntry(key.toLowerCase(), value)),
       );
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
}

abstract interface class HttpTransport {
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  });
  Future<void> close();
}
