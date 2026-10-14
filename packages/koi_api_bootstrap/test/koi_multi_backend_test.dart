import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap_native.dart';
import 'package:koi_network/koi_network.dart';

void main() {
  tearDown(disposeKoiApi);

  test('failed GET and POST requests are sent once on every backend', () async {
    final runtime = await bootstrapKoiApi(
      const KoiApiBootstrapOptions(
        baseUrl: 'https://account.example.com/',
        environment: 'test',
        primaryBackendKey: 'account',
        additionalBackends: [
          KoiBackendDefinition(
            key: 'reporting',
            purpose: 'Reports',
            baseUrl: 'https://reports.example.com/',
          ),
        ],
      ),
    );
    for (final backend in runtime.backendKeys) {
      final client = buildKoiApiClient(runtime, backend, (dio) => dio);
      final adapter = _UnavailableAdapter();
      client.httpClientAdapter = adapter;
      await expectLater(
        client.get<void>('unavailable'),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        client.post<void>('unavailable', data: {'operation': 'create'}),
        throwsA(isA<DioException>()),
      );
      expect(adapter.methods, ['GET', 'POST'], reason: backend);
    }
  });

  test(
    'named backends share session and isolate a delayed secondary 401',
    () async {
      final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final secondary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => primary.close(force: true));
      addTearDown(() => secondary.close(force: true));
      final primaryTokens = <String?>[];
      final secondaryTokens = <String?>[];
      final oldRequestReceived = Completer<void>();
      final releaseOldResponse = Completer<void>();
      primary.listen((request) async {
        primaryTokens.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'code': 0, 'data': 'ok'}));
        await request.response.close();
      });
      secondary.listen((request) async {
        secondaryTokens.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (request.uri.path == '/delayed') {
          oldRequestReceived.complete();
          await releaseOldResponse.future;
        }
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'code': 401, 'msg': 'expired'}));
        await request.response.close();
      });
      var unauthorizedCount = 0;
      final bindings = KoiApiBindings(
        tokenStorage: KoiMemoryTokenSession(initialToken: 'same-token'),
        onUnauthorized: (_, _) async => unauthorizedCount++,
      );
      final runtime = await bootstrapKoiApi(
        KoiApiBootstrapOptions(
          baseUrl: 'http://${primary.address.host}:${primary.port}/',
          environment: 'test',
          primaryBackendKey: 'account',
          additionalBackends: [
            KoiBackendDefinition(
              key: 'reporting',
              purpose: 'Reports in the account authentication domain',
              baseUrl: 'http://${secondary.address.host}:${secondary.port}/',
            ),
          ],
        ),
        bindings: bindings,
      );
      final account = buildKoiApiClient(runtime, 'account', (dio) => dio);
      final reporting = buildKoiApiClient(runtime, 'reporting', (dio) => dio);
      expect(runtime.backendKeys, {'account', 'reporting'});
      expect(account, same(KoiNetworkServiceManager.instance.mainDio));
      expect(reporting, isNot(same(account)));
      expect(() => runtime.backendKeys.clear(), throwsUnsupportedError);

      final oldRequest = reporting.get<void>('delayed');
      await oldRequestReceived.future;
      await bindings.tokenSession.clearToken();
      await bindings.tokenSession.saveToken('same-token');
      await account.get<void>('current');
      releaseOldResponse.complete();
      await expectLater(oldRequest, throwsA(isA<DioException>()));
      expect(bindings.tokenSession.getToken(), 'same-token');
      expect(unauthorizedCount, 0);

      await expectLater(
        reporting.get<void>('unauthorized'),
        throwsA(isA<DioException>()),
      );
      await account.get<void>('after-logout');
      expect(bindings.tokenSession.getToken(), isNull);
      expect(unauthorizedCount, 1);
      expect(primaryTokens, ['Bearer same-token', null]);
      expect(secondaryTokens, ['Bearer same-token', 'Bearer same-token']);

      await runtime.dispose();
      expect(KoiDioFactory.instanceKeys, isEmpty);
      expect(KoiNetworkAdapters.isRegistered, isFalse);
      expect(
        () => buildKoiApiClient(runtime, 'reporting', (dio) => dio),
        throwsStateError,
      );
    },
  );

  test('invalid replacement leaves the active runtime usable', () async {
    final runtime = await bootstrapKoiApi(
      const KoiApiBootstrapOptions(
        baseUrl: 'https://example.com/',
        environment: 'test',
      ),
    );
    final client = buildKoiApiClient(runtime, 'main', (dio) => dio);
    await expectLater(
      bootstrapKoiApi(
        const KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: 'prdo',
        ),
      ),
      throwsArgumentError,
    );
    expect(buildKoiApiClient(runtime, 'main', (dio) => dio), same(client));
    expect(
      () => buildKoiApiClient(runtime, 'missing', (dio) => dio),
      throwsArgumentError,
    );
  });

  test(
    'replacing runtime invalidates old client factories and stale dispose',
    () async {
      const options = KoiApiBootstrapOptions(
        baseUrl: 'https://example.com/',
        environment: 'test',
      );
      final old = await bootstrapKoiApi(options);
      final current = await bootstrapKoiApi(options);
      await old.dispose();
      expect(
        () => buildKoiApiClient(old, 'main', (dio) => dio),
        throwsStateError,
      );
      expect(buildKoiApiClient(current, 'main', (dio) => dio), isA<Dio>());
    },
  );

  test(
    'concurrent bootstrap cannot overwrite active global ownership',
    () async {
      const options = KoiApiBootstrapOptions(
        baseUrl: 'https://example.com/',
        environment: 'test',
      );
      final first = bootstrapKoiApi(options);
      final second = bootstrapKoiApi(options);
      await expectLater(second, throwsStateError);
      final runtime = await first;
      expect(buildKoiApiClient(runtime, 'main', (dio) => dio), isA<Dio>());
    },
  );

  test('initialization failure cleans every global resource', () async {
    await expectLater(
      bootstrapKoiApi(
        const KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: 'test',
          enableInternalLogging: true,
        ),
        bindings: KoiApiBindings(
          onLog: (_, _, _, _) => throw StateError('logger unavailable'),
        ),
      ),
      throwsStateError,
    );
    expect(KoiDioFactory.instanceKeys, isEmpty);
    expect(KoiNetworkAdapters.isRegistered, isFalse);
    expect(KoiNetworkConstants.debugEnabled, isFalse);
  });

  test(
    'production clears inherited debug state and emits no request data',
    () async {
      final devLogs = <String>[];
      final devRuntime = await bootstrapKoiApi(
        const KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: 'dev',
          enableInternalLogging: true,
        ),
        bindings: KoiApiBindings(
          onLog: (_, message, _, _) => devLogs.add(message),
        ),
      );
      expect(KoiNetworkConstants.debugEnabled, isTrue);
      expect(devLogs, isNotEmpty);
      await devRuntime.dispose();
      expect(KoiNetworkConstants.debugEnabled, isFalse);
      KoiNetworkConstants.debugEnabled = true;
      final productionLogs = <String>[];
      final production = await bootstrapKoiApi(
        const KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: 'production',
          validateCertificate: false,
        ),
        bindings: KoiApiBindings(
          onLog: (_, message, _, _) => productionLogs.add(message),
        ),
      );
      final client = buildKoiApiClient(production, 'main', (dio) => dio);
      client.httpClientAdapter = _BadRequestAdapter();
      await expectLater(
        client.get<void>(
          'private',
          queryParameters: {'secret': 'query-secret'},
        ),
        throwsA(isA<DioException>()),
      );
      expect(KoiNetworkConstants.debugEnabled, isFalse);
      expect(
        KoiNetworkServiceManager.instance.config!.validateCertificate,
        isTrue,
      );
      expect(productionLogs, isEmpty);
      await production.dispose();
      expect(KoiNetworkConstants.debugEnabled, isFalse);
    },
  );
}

final class _BadRequestAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'code': 400, 'msg': 'response-secret'}),
    400,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

final class _UnavailableAdapter implements HttpClientAdapter {
  final methods = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    return ResponseBody.fromString(
      jsonEncode({'code': 503, 'msg': 'unavailable'}),
      503,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
