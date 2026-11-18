import 'dart:async';
import 'dart:typed_data';

import 'package:koi_core/koi_core.dart';
import 'package:koi_network/koi_network.dart';

/// Private Dio adapter; the public bootstrap API stays client independent.
final class DiagnosticInterceptor extends Interceptor {
  static const _trace = 'koi.diagnostic.trace';
  static const _request = 'koi.diagnostic.request';
  static const _attempt = 'koi.diagnostic.attempt';
  static int _nextRequest = 0;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = options.extra.putIfAbsent(
      _request,
      () => '${DateTime.now().microsecondsSinceEpoch}-${++_nextRequest}',
    );
    final attempt = (options.extra[_attempt] as int? ?? 0) + 1;
    options.extra[_attempt] = attempt;
    options.extra[_trace] = Diagnostics.startNetwork(
      options.method,
      options.uri,
      headers: options.headers,
      body: options.data is FormData
          ? {
              'fields': Map<String, String>.fromEntries(
                (options.data as FormData).fields,
              ),
              'files': [
                for (final file in (options.data as FormData).files)
                  {
                    'field': file.key,
                    'name': file.value.filename,
                    'bytes': file.value.length,
                    'type': '${file.value.contentType}',
                  },
              ],
            }
          : options.data is Stream
          ? '[stream upload]'
          : options.data,
      requestId: '$id',
      attempt: attempt,
    );
    handler.next(options);
  }

  void _response(Response<dynamic>? response) {
    final trace = response?.requestOptions.extra[_trace] as DiagnosticTrace?;
    trace?.response(
      response?.statusCode,
      response?.headers.map,
      body: response?.requestOptions.responseType == ResponseType.bytes
          ? {'kind': 'binary', 'bytes': (response?.data as List?)?.length}
          : response?.data is ResponseBody
          ? '[stream; not captured]'
          : response?.data,
    );
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _response(response);
    final trace = response.requestOptions.extra[_trace] as DiagnosticTrace?;
    final body = response.data;
    if (trace != null && body is ResponseBody) {
      body.stream = _observeStream(
        body.stream,
        trace,
        response.requestOptions.cancelToken,
      );
    } else {
      trace?.finish();
    }
    handler.next(response);
  }

  Stream<Uint8List> _observeStream(
    Stream<Uint8List> source,
    DiagnosticTrace trace,
    CancelToken? cancelToken,
  ) {
    DiagnosticTrace? pending = trace;
    void finish({Object? error, bool cancelled = false}) {
      pending?.finish(error: error, cancelled: cancelled);
      pending = null;
    }

    // Cancellation may arrive before the consumer listens to the response.
    // Drop the trace reference on completion even if the token is retained.
    cancelToken?.whenCancel.then((error) {
      finish(error: error.type.name, cancelled: true);
    });
    late final StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? subscription;
    var done = false;
    controller = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: (Object error, StackTrace stack) {
            finish(
              error: error is DioException ? error.type.name : error,
              cancelled:
                  error is DioException &&
                  error.type == DioExceptionType.cancel,
            );
            controller.addError(error, stack);
          },
          onDone: () {
            done = true;
            finish();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        if (!done) finish(cancelled: true);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _response(err.response);
    (err.requestOptions.extra[_trace] as DiagnosticTrace?)?.finish(
      error: err.type.name,
      cancelled: err.type == DioExceptionType.cancel,
    );
    handler.next(err);
  }
}
