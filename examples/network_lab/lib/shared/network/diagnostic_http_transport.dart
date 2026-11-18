import 'dart:convert';

import 'package:koi_core/koi_core.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

/// Observes only the stream the consumer reads, without eager buffering.
final class DiagnosticHttpTransport implements HttpTransport {
  DiagnosticHttpTransport(this.inner);
  final HttpTransport inner;
  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    final trace = Diagnostics.startNetwork(method, uri, headers: headers);
    if (trace == null) {
      return inner.open(
        uri,
        cancellation: cancellation,
        method: method,
        headers: headers,
      );
    }
    final detach = cancellation.onCancel(() => trace.finish(cancelled: true));
    try {
      final result = await inner.open(
        uri,
        cancellation: cancellation,
        method: method,
        headers: headers,
      );
      trace.response(result.status, result.headers);
      Stream<List<int>> observed() async* {
        final sample = <int>[];
        var total = 0;
        var complete = false;
        try {
          await for (final bytes in result.body) {
            total += bytes.length;
            if (sample.length < 65536) {
              sample.addAll(bytes.take(65536 - sample.length));
            }
            yield bytes;
          }
          complete = true;
          final type = result.headers['content-type'] ?? '';
          trace.finish(
            body: {
              'sample': type.contains('json') || type.startsWith('text/')
                  ? diagnosticSnapshot(
                      utf8.decode(sample, allowMalformed: true),
                    )
                  : '[binary]',
              'bytes': total,
              'truncated': total > sample.length,
            },
          );
        } catch (error) {
          trace.finish(error: error);
          rethrow;
        } finally {
          if (!complete) trace.finish(cancelled: true);
          detach();
        }
      }

      return HttpPayload(
        status: result.status,
        headers: result.headers,
        body: observed(),
      );
    } catch (error) {
      detach();
      trace.finish(error: error, cancelled: cancellation.isCancelled);
      rethrow;
    }
  }

  @override
  Future<void> close() => inner.close();
}
