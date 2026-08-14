import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_admin_app/app.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';
import 'package:koi_admin_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:koi_admin_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:koi_admin_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_core/koi_core.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = AppEnvironment.current;
  _validateEnvironment(environment);
  final dataSource = _createAuthDataSource(environment);

  final unauthorizedBridge = _UnauthorizedBridge();
  final bindings = KoiApiBindings(
    tokenStorage: await createDefaultTokenSession(),
    onUnauthorized: unauthorizedBridge.handle,
    onError: (message) {
      AppLogger.error(message);
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('网络请求失败，请稍后重试')),
      );
    },
    onLog: (level, message, error, stackTrace) {
      AppLogger.log(
        switch (level) {
          KoiApiLogLevel.debug => AppLogLevel.debug,
          KoiApiLogLevel.info => AppLogLevel.info,
          KoiApiLogLevel.warning => AppLogLevel.warning,
          KoiApiLogLevel.error || KoiApiLogLevel.fatal => AppLogLevel.error,
        },
        message,
        error: error,
        stackTrace: stackTrace,
      );
    },
  );

  await bootstrapKoiApi(
    KoiApiBootstrapOptions(
      baseUrl: environment.apiBaseUrl,
      environment: environment.name,
      enableLogging: environment.enableNetworkLog,
      enableInternalLogging: environment.enableNetworkLog,
      validateCertificate: true,
    ),
    bindings: bindings,
  );

  final repository = AuthRepositoryImpl(
    dataSource: dataSource,
    tokenSession: bindings.tokenSession,
  );
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  unauthorizedBridge.attach(
    () => container.read(authControllerProvider.notifier).handleUnauthorized(),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KoiBlueprintAdminApp(),
    ),
  );
}

AuthDataSource _createAuthDataSource(AppEnvironment environment) {
  if (environment.usesMockAuth) {
    return MockAuthDataSource();
  }
  throw StateError('staging/prod 必须在 bootstrap.dart 注入真实认证数据源');
}

void _validateEnvironment(AppEnvironment environment) {
  final uri = Uri.tryParse(environment.apiBaseUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw StateError('API Base URL 无效：${environment.apiBaseUrl}');
  }
  if (!environment.usesMockAuth && uri.scheme != 'https') {
    throw StateError('staging/prod API 必须使用 HTTPS');
  }
  if (!environment.usesMockAuth && uri.host.endsWith('example.com')) {
    throw StateError('staging/prod 启动前必须配置真实 API Base URL');
  }
}

final class _UnauthorizedBridge {
  Future<void> Function()? _handler;

  void attach(Future<void> Function() handler) {
    _handler = handler;
  }

  Future<void> handle(int? statusCode, String? message) async {
    await _handler?.call();
  }
}
