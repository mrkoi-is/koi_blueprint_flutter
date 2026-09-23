import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';
import 'package:koi_api_bootstrap/src/koi_api_bootstrap_options.dart';
import 'package:koi_api_bootstrap/src/koi_api_log.dart';
import 'package:koi_api_bootstrap/src/koi_api_runtime.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';
import 'package:koi_network/koi_network.dart';

const _sessionRevisionExtraKey = 'koi_api_session_revision';
const _sessionTokenExtraKey = 'koi_api_session_token';

_NativeKoiApiRuntime? _activeRuntime;

Future<KoiApiRuntime> bootstrapKoiApiBackend(
  KoiApiBootstrapOptions options,
  KoiApiBindings bindings,
) async {
  await disposeKoiApiBackend();

  KoiNetworkConstants.debugEnabled = options.enableInternalLogging;
  KoiNetworkAdapters.register(
    authAdapter: _SessionAuthAdapter(bindings.tokenSession),
    errorHandlerAdapter: _BindingsErrorHandlerAdapter(bindings),
    loadingAdapter: KoiDefaultLoadingAdapter(),
    platformAdapter: KoiDefaultPlatformAdapter(),
    loggerAdapter: _BindingsLoggerAdapter(bindings),
    responseParser: const KoiDefaultResponseParser(),
    requestEncoder: const KoiJsonRequestEncoder(),
  );

  final config = KoiNetworkConfig.create(
    baseUrl: options.baseUrl,
    enableLogging: options.enableLogging,
    validateCertificate: options.isProduction || options.validateCertificate,
    enableProactiveTokenRefresh: options.enableProactiveTokenRefresh,
    tokenRefreshWhiteList: options.tokenRefreshWhiteList,
    headerBuilders: [
      (requestOptions) async {
        final token = bindings.tokenSession.getToken();
        requestOptions.extra[_sessionRevisionExtraKey] =
            bindings.tokenSession.revision;
        requestOptions.extra[_sessionTokenExtraKey] = token;
        if (token == null || token.isEmpty) {
          return <String, String>{};
        }
        return <String, String>{'Authorization': 'Bearer $token'};
      },
    ],
  );

  try {
    await KoiNetworkInitializer.initializeWithConfig(config);
    KoiNetworkServiceManager.instance.mainDio.interceptors.insert(
      0,
      _SessionAwareAuthErrorInterceptor(
        bindings,
        options.tokenRefreshWhiteList,
      ),
    );
  } catch (_) {
    await disposeKoiApiBackend();
    rethrow;
  }

  final runtime = _NativeKoiApiRuntime(bindings);
  _activeRuntime = runtime;
  return runtime;
}

Future<void> disposeKoiApiBackend() async {
  _activeRuntime?._markDisposed();
  _activeRuntime = null;
  KoiNetworkInitializer.dispose();
  KoiNetworkAdapters.clear();
  KoiNetworkConstants.debugEnabled = false;
}

final class _SessionAuthAdapter extends KoiAuthAdapter {
  _SessionAuthAdapter(this._session);

  final KoiTokenSession _session;

  @override
  String? getToken() => _session.getToken();

  @override
  Future<bool> refresh() async => false;

  @override
  Future<void> saveToken(String token) => _session.saveToken(token);

  @override
  Future<void> clearToken() => _session.clearToken();
}

final class _BindingsErrorHandlerAdapter extends KoiErrorHandlerAdapter {
  _BindingsErrorHandlerAdapter(this._bindings);

  final KoiApiBindings _bindings;

  @override
  void showError(String message) => _bindings.reportError(message);

  @override
  Future<bool> handleAuthError({int? statusCode, String? message}) {
    // koi_network 不会向此适配器暴露失败请求。登出判断由下方的会话感知拦截器负责，
    // 避免旧请求延迟返回的 401 撤销较新的令牌。
    return Future<bool>.value(true);
  }

  @override
  String formatErrorMessage(Object error) => error.toString();
}

final class _SessionAwareAuthErrorInterceptor extends Interceptor {
  _SessionAwareAuthErrorInterceptor(
    this._bindings,
    this._tokenRefreshWhiteList,
  );

  final KoiApiBindings _bindings;
  final List<String> _tokenRefreshWhiteList;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_tokenRefreshWhiteList.any(err.requestOptions.path.contains)) {
      handler.next(err);
      return;
    }

    final body = err.response?.data;
    final mapBody = body is Map<String, dynamic> ? body : null;
    final isAuthError = KoiNetworkAdapters.responseParser.isAuthError(
      err.response?.statusCode,
      mapBody,
    );
    final requestToken = _readBearerToken(err.requestOptions.headers);
    final snapshotToken = err.requestOptions.extra[_sessionTokenExtraKey];
    final snapshotRevision = err.requestOptions.extra[_sessionRevisionExtraKey];
    final expectedToken = snapshotToken is String
        ? snapshotToken
        : requestToken;
    final expectedRevision = snapshotRevision is int ? snapshotRevision : null;

    if (isAuthError && expectedToken != null) {
      try {
        String? message;
        try {
          message = KoiNetworkAdapters.responseParser.getMessage(mapBody ?? {});
        } catch (error, stackTrace) {
          _bindings.log(
            KoiApiLogLevel.warning,
            'Could not parse the unauthorized response message',
            error,
            stackTrace,
          );
        }
        await _bindings.handleUnauthorized(
          statusCode: err.response?.statusCode,
          message: message,
          expectedToken: expectedToken,
          expectedRevision: expectedRevision,
        );
      } catch (error, stackTrace) {
        _bindings.log(
          KoiApiLogLevel.error,
          'Failed to process an unauthorized response',
          error,
          stackTrace,
        );
      }
    }

    handler.next(err);
  }

  String? _readBearerToken(Map<String, dynamic> headers) {
    Object? authorization;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        authorization = entry.value;
        break;
      }
    }

    final value = authorization?.toString().trim();
    if (value == null || value.length <= 7) {
      return null;
    }
    if (value.substring(0, 7).toLowerCase() != 'bearer ') {
      return null;
    }
    return value.substring(7);
  }
}

final class _BindingsLoggerAdapter implements KoiLoggerAdapter {
  _BindingsLoggerAdapter(this._bindings);

  final KoiApiBindings _bindings;

  @override
  void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _bindings.log(KoiApiLogLevel.debug, message, error, stackTrace);
  }

  @override
  void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _bindings.log(KoiApiLogLevel.info, message, error, stackTrace);
  }

  @override
  void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _bindings.log(KoiApiLogLevel.warning, message, error, stackTrace);
  }

  @override
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _bindings.log(KoiApiLogLevel.error, message, error, stackTrace);
  }

  @override
  void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _bindings.log(KoiApiLogLevel.fatal, message, error, stackTrace);
  }
}

final class _NativeKoiApiRuntime implements KoiApiRuntime {
  _NativeKoiApiRuntime(this.bindings);

  @override
  final KoiApiBindings bindings;

  bool _disposed = false;

  @override
  KoiApiBackend get backend => KoiApiBackend.native;

  @override
  bool get isNoop => false;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (identical(_activeRuntime, this)) {
      await disposeKoiApiBackend();
    } else {
      _markDisposed();
    }
  }

  void _markDisposed() {
    _disposed = true;
  }
}
