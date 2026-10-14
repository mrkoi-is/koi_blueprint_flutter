import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:network_lab/shared/network/domain/http_ports.dart';

HttpTransport createHttpTransport() => FetchHttpTransport();

/// Fetch ReadableStream and AbortController are used directly: browser XHR/Dio
/// response buffering does not provide streaming backpressure for downloads.
final class FetchHttpTransport implements HttpTransport {
  final _active = <web.AbortController>{};
  bool _closed = false;
  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    if (_closed) throw StateError('HTTP transport closed');
    cancellation.check();
    final abort = web.AbortController();
    _active.add(abort);
    final detach = cancellation.onCancel(() => abort.abort());
    try {
      final requestHeaders = web.Headers();
      headers.forEach((name, value) => requestHeaders.set(name, value));
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: method,
              headers: requestHeaders,
              signal: abort.signal,
              cache: 'no-store',
            ),
          )
          .toDart;
      final responseHeaders = <String, String>{};
      for (final name in [
        'content-length',
        'content-range',
        'etag',
        'accept-ranges',
        'content-type',
      ]) {
        final value = response.headers.get(name);
        if (value != null) responseHeaders[name] = value;
      }
      Stream<List<int>> stream() async* {
        web.ReadableStreamDefaultReader? reader;
        try {
          final body = response.body;
          if (body != null) {
            reader = web.ReadableStreamDefaultReader(body);
            while (true) {
              cancellation.check();
              final part = await reader.read().toDart;
              if (part.done) break;
              yield (part.value as JSUint8Array).toDart;
            }
          }
          cancellation.check();
        } catch (_) {
          cancellation.check();
          rethrow;
        } finally {
          if (reader != null) {
            try {
              await reader.cancel().toDart;
            } catch (_) {
              /* Already aborted. */
            }
            reader.releaseLock();
          }
          abort.abort();
          detach();
          _active.remove(abort);
        }
      }

      return HttpPayload(
        status: response.status,
        headers: responseHeaders,
        body: stream(),
      );
    } catch (_) {
      detach();
      _active.remove(abort);
      abort.abort();
      cancellation.check();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final value in _active) {
      value.abort();
    }
    _active.clear();
  }
}
