import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/core/network/app_network_container.dart';
import 'package:koi_admin_app/core/network/app_network_container_stub.dart'
    as web;
import 'package:koi_admin_app/core/providers/system_status_providers.dart';
import 'package:koi_admin_app/features/system/domain/system_status_gateway.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap_native.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  late KoiApiRuntime runtime;
  late _ResponseAdapter adapter;
  late AppNetworkContainer network;

  setUp(() async {
    runtime = await bootstrapKoiApi(
      const KoiApiBootstrapOptions(
        baseUrl: 'https://runtime.example.com/admin/',
        environment: 'test',
      ),
      bindings: KoiApiBindings(
        tokenStorage: KoiMemoryTokenSession(initialToken: 'test-token'),
      ),
    );
    adapter = _ResponseAdapter();
    buildKoiApiClient(runtime, 'main', (dio) {
      dio.httpClientAdapter = adapter;
      return dio;
    });
    network = AppNetworkContainer.fromRuntime(runtime);
  });

  tearDown(() async => runtime.dispose());

  test(
    'generated client uses runtime host, prefix and shared session',
    () async {
      final result = await network.systemStatusGateway.readHealth();
      final health = result.getOrElse(
        (failure) => throw StateError('$failure'),
      );
      expect(health.state, SystemServiceState.healthy);
      expect(health.version, '1.2.3');
      expect(adapter.request?.method, 'GET');
      expect(
        adapter.request?.uri.toString(),
        'https://runtime.example.com/admin/health',
      );
      expect(adapter.request?.headers['Authorization'], 'Bearer test-token');
    },
  );

  test('DTO statuses map to stable domain states', () async {
    for (final entry in {
      'degraded': SystemServiceState.degraded,
      'unknown': SystemServiceState.unknown,
      'future_status': SystemServiceState.unknown,
    }.entries) {
      adapter.body = '{"status":"${entry.key}"}';
      final result = await network.systemStatusGateway.readHealth();
      expect(
        result.getOrElse((failure) => throw StateError('$failure')).state,
        entry.value,
      );
    }
  });

  test(
    'transport and contract failures stay behind the domain boundary',
    () async {
      adapter.statusCode = 503;
      final unavailable = await network.systemStatusGateway.readHealth();
      expect(
        unavailable.swap().getOrElse(
          (_) => throw StateError('expected failure'),
        ),
        isA<NetworkFailure>(),
      );
      adapter.statusCode = 401;
      final unauthorized = await network.systemStatusGateway.readHealth();
      expect(
        unauthorized.swap().getOrElse(
          (_) => throw StateError('expected failure'),
        ),
        isA<UnauthorizedFailure>(),
      );
      adapter.statusCode = 200;
      adapter.body = '{}';
      final invalid = await network.systemStatusGateway.readHealth();
      expect(
        invalid.swap().getOrElse((_) => throw StateError('expected failure')),
        isA<SerializationFailure>(),
      );
    },
  );

  test(
    'Web placeholder reports unavailable instead of contacting a host',
    () async {
      final result = await web
          .createAppNetworkContainer(runtime)
          .systemStatusGateway
          .readHealth();
      expect(result.isLeft(), isTrue);
      expect(adapter.request, isNull);
    },
  );

  test(
    'gateway provider requires composition and accepts a domain override',
    () {
      final missing = ProviderContainer();
      addTearDown(missing.dispose);
      expect(() => missing.read(systemStatusGatewayProvider), throwsException);
      final container = ProviderContainer(
        overrides: [
          systemStatusGatewayProvider.overrideWithValue(
            network.systemStatusGateway,
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(systemStatusGatewayProvider),
        same(network.systemStatusGateway),
      );
    },
  );
}

final class _ResponseAdapter implements HttpClientAdapter {
  String body = '{"status":"ok","version":"1.2.3"}';
  int statusCode = 200;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
