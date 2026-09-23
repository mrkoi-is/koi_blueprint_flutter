import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_network/koi_network.dart';

void main() {
  tearDown(disposeKoiApi);

  group('KoiMemoryTokenSession', () {
    test('saves, reads, and clears a token', () async {
      final session = KoiMemoryTokenSession();

      expect(session.getToken(), isNull);
      expect(session.hasToken, isFalse);

      await session.saveToken('access-token');
      expect(session.getToken(), 'access-token');
      expect(session.hasToken, isTrue);

      await session.clearToken();
      expect(session.getToken(), isNull);
      expect(session.hasToken, isFalse);
    });

    test('rejects an empty token', () async {
      final session = KoiMemoryTokenSession();

      await expectLater(session.saveToken(''), throwsArgumentError);
    });
  });

  group('KoiRevocableTokenSession', () {
    test('masks a token before a failing clear reaches storage', () async {
      final storage = _FailingTokenSession();
      final session = KoiRevocableTokenSession(storage);

      await expectLater(session.clearToken(), throwsStateError);

      expect(storage.hasToken, isTrue);
      expect(session.hasToken, isFalse);
      expect(session.getToken(), isNull);
    });

    test('successful save makes a replacement token readable again', () async {
      final storage = KoiMemoryTokenSession(initialToken: 'expired-token');
      final session = KoiRevocableTokenSession(storage);
      await session.clearToken();

      await session.saveToken('replacement-token');

      expect(session.getToken(), 'replacement-token');
    });
  });

  group('KoiApiBindings', () {
    test('clears the token before invoking unauthorized callback', () async {
      final session = KoiMemoryTokenSession(initialToken: 'expired-token');
      String? observedToken;
      int? observedStatus;
      String? observedMessage;
      final bindings = KoiApiBindings(
        tokenStorage: session,
        onUnauthorized: (statusCode, message) async {
          observedToken = session.getToken();
          observedStatus = statusCode;
          observedMessage = message;
        },
      );

      final handled = await bindings.handleUnauthorized(
        statusCode: 401,
        message: 'expired',
      );

      expect(handled, isTrue);
      expect(observedToken, isNull);
      expect(observedStatus, 401);
      expect(observedMessage, 'expired');
    });

    test('coalesces concurrent unauthorized callbacks', () async {
      final session = KoiMemoryTokenSession(initialToken: 'expired-token');
      final callbackStarted = Completer<void>();
      final releaseCallback = Completer<void>();
      var callbackCount = 0;
      final bindings = KoiApiBindings(
        tokenStorage: session,
        onUnauthorized: (statusCode, message) async {
          callbackCount++;
          callbackStarted.complete();
          await releaseCallback.future;
        },
      );

      final first = bindings.handleUnauthorized(statusCode: 401);
      await callbackStarted.future;
      final second = bindings.handleUnauthorized(statusCode: 401);
      releaseCallback.complete();

      await Future.wait([first, second]);
      expect(callbackCount, 1);
    });

    test('forwards error and log callbacks without network types', () {
      String? errorMessage;
      final logs = <KoiApiLogLevel>[];
      final bindings = KoiApiBindings(
        onError: (message) => errorMessage = message,
        onLog: (level, message, error, stackTrace) => logs.add(level),
      );

      bindings.reportError('request failed');
      bindings.log(KoiApiLogLevel.warning, 'retrying');

      expect(errorMessage, 'request failed');
      expect(logs, [KoiApiLogLevel.warning]);
    });

    test(
      'revokes requests and notifies logout when token clear fails',
      () async {
        final session = _FailingTokenSession();
        var callbackCount = 0;
        final bindings = KoiApiBindings(
          tokenStorage: session,
          onUnauthorized: (statusCode, message) async => callbackCount++,
        );

        await expectLater(
          bindings.handleUnauthorized(statusCode: 401),
          throwsA(isA<StateError>()),
        );
        expect(callbackCount, 1);
        expect(session.hasToken, isTrue);
        expect(bindings.tokenSession.hasToken, isFalse);
      },
    );

    test('ignores an unauthorized response from a replaced token', () async {
      final bindings = KoiApiBindings(
        tokenStorage: KoiMemoryTokenSession(initialToken: 'old-token'),
      );
      await bindings.tokenSession.clearToken();
      await bindings.tokenSession.saveToken('new-token');

      final handled = await bindings.handleUnauthorized(
        statusCode: 401,
        expectedToken: 'old-token',
      );

      expect(handled, isFalse);
      expect(bindings.tokenSession.getToken(), 'new-token');
    });

    test(
      'does not notify logout when a new login starts during token clear',
      () async {
        final storage = _DelayedClearTokenSession();
        var callbackCount = 0;
        final bindings = KoiApiBindings(
          tokenStorage: storage,
          onUnauthorized: (statusCode, message) async => callbackCount++,
        );

        final unauthorized = bindings.handleUnauthorized(
          statusCode: 401,
          expectedToken: 'old-token',
        );
        await storage.clearStarted.future;
        final newLogin = bindings.tokenSession.saveToken('new-token');
        storage.releaseClear.complete();

        expect(await unauthorized, isFalse);
        await newLogin;
        expect(callbackCount, 0);
        expect(bindings.tokenSession.getToken(), 'new-token');
      },
    );
  });

  test('native runtime initializes with secure and quiet defaults', () async {
    const options = KoiApiBootstrapOptions(
      baseUrl: 'https://example.com/',
      environment: 'prod',
      validateCertificate: false,
    );
    final logs = <KoiApiLogLevel>[];
    final bindings = KoiApiBindings(
      onLog: (level, message, error, stackTrace) => logs.add(level),
    );

    final runtime = await bootstrapKoiApi(options, bindings: bindings);

    expect(options.enableLogging, isFalse);
    expect(options.enableProactiveTokenRefresh, isFalse);
    expect(options.isProduction, isTrue);
    expect(runtime.backend, KoiApiBackend.native);
    expect(runtime.isNoop, isFalse);
    expect(runtime.bindings, same(bindings));
    expect(logs, isEmpty);
    expect(
      KoiNetworkServiceManager.instance.config?.validateCertificate,
      isTrue,
    );

    await runtime.dispose();
  });

  test('native error handler clears token and reports one 401', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'code': 401, 'msg': 'expired'}));
      await request.response.close();
    });

    final session = KoiMemoryTokenSession(initialToken: 'expired-token');
    var unauthorizedCount = 0;
    int? observedStatus;
    final bindings = KoiApiBindings(
      tokenStorage: session,
      onUnauthorized: (statusCode, message) async {
        unauthorizedCount++;
        observedStatus = statusCode;
      },
    );
    final runtime = await bootstrapKoiApi(
      KoiApiBootstrapOptions(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        environment: 'test',
        enableProactiveTokenRefresh: false,
      ),
      bindings: bindings,
    );

    await expectLater(
      KoiNetworkServiceManager.instance.mainDio.get<void>('protected'),
      throwsA(isA<Object>()),
    );

    expect(session.getToken(), isNull);
    expect(unauthorizedCount, 1);
    expect(observedStatus, 401);
    await runtime.dispose();
  });

  test('a whitelisted 401 does not revoke the current session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'code': 401, 'msg': 'expired'}));
      await request.response.close();
    });

    var unauthorizedCount = 0;
    final bindings = KoiApiBindings(
      tokenStorage: KoiMemoryTokenSession(initialToken: 'current-token'),
      onUnauthorized: (statusCode, message) async => unauthorizedCount++,
    );
    final runtime = await bootstrapKoiApi(
      KoiApiBootstrapOptions(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        environment: 'test',
        enableProactiveTokenRefresh: false,
        tokenRefreshWhiteList: const ['public'],
      ),
      bindings: bindings,
    );

    await expectLater(
      KoiNetworkServiceManager.instance.mainDio.get<void>('public'),
      throwsA(isA<Object>()),
    );

    expect(bindings.tokenSession.getToken(), 'current-token');
    expect(unauthorizedCount, 0);
    await runtime.dispose();
  });

  test('a structured 401 message still revokes the session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {'message': 'expired'},
          }),
        );
      await request.response.close();
    });

    var unauthorizedCount = 0;
    final bindings = KoiApiBindings(
      tokenStorage: KoiMemoryTokenSession(initialToken: 'expired-token'),
      onUnauthorized: (statusCode, message) async => unauthorizedCount++,
    );
    final runtime = await bootstrapKoiApi(
      KoiApiBootstrapOptions(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        environment: 'test',
        enableProactiveTokenRefresh: false,
      ),
      bindings: bindings,
    );

    await expectLater(
      KoiNetworkServiceManager.instance.mainDio.get<void>('protected'),
      throwsA(isA<Object>()),
    );

    expect(bindings.tokenSession.getToken(), isNull);
    expect(unauthorizedCount, 1);
    await runtime.dispose();
  });

  test('delayed 401 from an old request preserves a newer token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestReceived = Completer<void>();
    final releaseResponse = Completer<void>();
    server.listen((request) async {
      if (!requestReceived.isCompleted) {
        requestReceived.complete();
        await releaseResponse.future;
      }
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'code': 401, 'msg': 'expired'}));
      await request.response.close();
    });

    var unauthorizedCount = 0;
    final bindings = KoiApiBindings(
      tokenStorage: KoiMemoryTokenSession(initialToken: 'old-token'),
      onUnauthorized: (statusCode, message) async => unauthorizedCount++,
    );
    final runtime = await bootstrapKoiApi(
      KoiApiBootstrapOptions(
        baseUrl: 'http://${server.address.host}:${server.port}/',
        environment: 'test',
        enableProactiveTokenRefresh: false,
      ),
      bindings: bindings,
    );

    final oldRequest = KoiNetworkServiceManager.instance.mainDio.get<void>(
      'protected',
    );
    await requestReceived.future;
    await bindings.tokenSession.clearToken();
    await bindings.tokenSession.saveToken('new-token');
    releaseResponse.complete();

    await expectLater(oldRequest, throwsA(isA<Object>()));
    expect(bindings.tokenSession.getToken(), 'new-token');
    expect(unauthorizedCount, 0);
    await runtime.dispose();
  });

  test(
    'delayed 401 cannot revoke a replacement session with the same token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestReceived = Completer<void>();
      final releaseResponse = Completer<void>();
      server.listen((request) async {
        if (!requestReceived.isCompleted) {
          requestReceived.complete();
          await releaseResponse.future;
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
        onUnauthorized: (statusCode, message) async => unauthorizedCount++,
      );
      final runtime = await bootstrapKoiApi(
        KoiApiBootstrapOptions(
          baseUrl: 'http://${server.address.host}:${server.port}/',
          environment: 'test',
          enableProactiveTokenRefresh: false,
        ),
        bindings: bindings,
      );

      final oldRequest = KoiNetworkServiceManager.instance.mainDio.get<void>(
        'protected',
      );
      await requestReceived.future;
      await bindings.tokenSession.clearToken();
      await bindings.tokenSession.saveToken('same-token');
      releaseResponse.complete();

      await expectLater(oldRequest, throwsA(isA<Object>()));
      expect(bindings.tokenSession.getToken(), 'same-token');
      expect(unauthorizedCount, 0);
      await runtime.dispose();
    },
  );
}

final class _FailingTokenSession implements KoiTokenSession {
  @override
  bool get hasToken => true;

  @override
  String? getToken() => 'token';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {
    throw StateError('clear failed');
  }
}

final class _DelayedClearTokenSession implements KoiTokenSession {
  final clearStarted = Completer<void>();
  final releaseClear = Completer<void>();
  String? _token = 'old-token';

  @override
  bool get hasToken => _token != null;

  @override
  String? getToken() => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    clearStarted.complete();
    await releaseClear.future;
    _token = null;
  }
}
