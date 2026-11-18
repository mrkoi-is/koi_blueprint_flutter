import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_api_bootstrap/src/backend/diagnostic_interceptor.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_network/koi_network.dart';

void main() {
  group('streaming diagnostics', () {
    late BoundedDiagnosticStore store;
    late void Function() unregister;
    late _StreamAdapter adapter;
    late Dio dio;
    setUp(() {
      store = BoundedDiagnosticStore();
      unregister = Diagnostics.register(store.record);
      adapter = _StreamAdapter();
      dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(DiagnosticInterceptor());
    });
    tearDown(() async {
      unregister();
      dio.close(force: true);
      await adapter.controller.close();
      await store.close();
    });
    Future<ResponseBody> open({CancelToken? cancelToken}) async =>
        (await dio.get<ResponseBody>(
          'https://fixture.invalid/stream',
          options: Options(responseType: ResponseType.stream),
          cancelToken: cancelToken,
        )).data!;
    test('waits for the body and preserves bytes, pause and resume', () async {
      final body = await open();
      expect(store.snapshot.last.network!['state'], 'receiving');
      expect(store.snapshot.last.network!.containsKey('durationMs'), isFalse);
      final bytes = <int>[];
      final done = Completer<void>();
      final subscription = body.stream.listen(
        bytes.addAll,
        onDone: done.complete,
      );
      addTearDown(subscription.cancel);
      subscription.pause();
      adapter.controller.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.paused, isTrue);
      expect(bytes, isEmpty);
      expect(store.snapshot.last.network!['state'], 'receiving');
      subscription.resume();
      await adapter.controller.close();
      await done.future;
      expect(bytes, [1, 2, 3]);
      final network = store.snapshot.last.network!;
      expect(network['state'], 'complete');
      expect(
        network['durationMs'] as int,
        greaterThan(network['headersMs'] as int),
      );
    });
    test(
      'propagates a body error and records failure instead of success',
      () async {
        final body = await open();
        final failure = StateError('body interrupted');
        final consumed = expectLater(
          body.stream.drain<void>(),
          throwsA(same(failure)),
        );
        adapter.controller.addError(failure, StackTrace.current);
        await consumed;
        expect(store.snapshot.last.network!['state'], 'failed');
        expect(
          store.snapshot.where((e) => e.network?['state'] == 'complete'),
          isEmpty,
        );
      },
    );
    test(
      'consumer cancellation finishes a pending body exactly once',
      () async {
        final body = await open();
        final subscription = body.stream.listen((_) {});
        addTearDown(subscription.cancel);
        await subscription.cancel();
        expect(store.snapshot.last.network!['state'], 'cancelled');
        await adapter.controller.close();
        expect(
          store.snapshot.where((e) => e.network?['state'] == 'cancelled'),
          hasLength(1),
        );
        expect(
          store.snapshot.where((e) => e.network?['state'] == 'complete'),
          isEmpty,
        );
      },
    );
    test('CancelToken cancels the trace before the consumer listens', () async {
      final token = CancelToken();
      final body = await open(cancelToken: token);
      token.cancel('stop reading');
      await Future<void>.delayed(Duration.zero);
      expect(store.snapshot.last.network!['state'], 'cancelled');
      await expectLater(
        body.stream.drain<void>(),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(
        store.snapshot.where((e) => e.network?['state'] == 'cancelled'),
        hasLength(1),
      );
    });
  });
  test(
    'Dio records success and failures without changing the request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = request.uri.path == '/fail' ? 500 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'ok': true, 'access_token': 'response-secret'}),
        );
        await request.response.close();
      });
      final store = BoundedDiagnosticStore();
      final unregister = Diagnostics.register(store.record);
      final dio = Dio()..interceptors.add(DiagnosticInterceptor());
      try {
        final result = await dio.post<dynamic>(
          'http://127.0.0.1:${server.port}/ok?token=query-secret',
          data: {'password': 'request-secret'},
          options: Options(headers: {'Authorization': 'Bearer private'}),
        );
        expect(result.data['access_token'], 'response-secret');
        await expectLater(
          dio.get<dynamic>('http://127.0.0.1:${server.port}/fail'),
          throwsA(isA<DioException>()),
        );
        expect(
          store.snapshot.where((e) => e.network?['state'] == 'complete').length,
          1,
        );
        expect(
          store.snapshot.where((e) => e.network?['state'] == 'failed').length,
          1,
        );
        final text = jsonEncode(store.snapshot.map((e) => e.toJson()).toList());
        expect(text, isNot(contains('secret')));
        expect(text, isNot(contains('private')));
      } finally {
        unregister();
        dio.close(force: true);
        await server.close(force: true);
        await store.close();
      }
    },
  );
}

final class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter() {
    controller = StreamController<Uint8List>(
      onPause: () => paused = true,
      onResume: () => paused = false,
    );
  }
  late final StreamController<Uint8List> controller;
  bool paused = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(controller.stream, 200);
  @override
  void close({bool force = false}) {}
}
