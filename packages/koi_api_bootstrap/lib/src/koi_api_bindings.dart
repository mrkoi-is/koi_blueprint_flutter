import 'package:koi_api_bootstrap/src/koi_api_log.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

typedef KoiApiUnauthorizedCallback = Future<void> Function(
  int? statusCode,
  String? message,
);

typedef KoiApiErrorCallback = void Function(String message);

class KoiApiBindings {
  KoiApiBindings({
    KoiTokenSession? tokenStorage,
    this.onUnauthorized,
    this.onError,
    this.onLog,
  }) : tokenSession = KoiRevocableTokenSession(
         tokenStorage ?? KoiMemoryTokenSession(),
       );

  /// 仓库和网络适配器共用的规范会话。
  /// 传入构造函数的持久化存储不得绕过此会话直接使用。
  final KoiRevocableTokenSession tokenSession;
  final KoiApiUnauthorizedCallback? onUnauthorized;
  final KoiApiErrorCallback? onError;
  final KoiApiLogCallback? onLog;

  Future<bool>? _unauthorizedOperation;
  String? _unauthorizedToken;
  int? _unauthorizedRevision;

  /// 清除令牌，并且只调用一次未授权回调。
  ///
  /// 多个拦截器可能观察到同一个 401 响应。并发调用会共用同一操作；令牌清除后，
  /// 后续调用将不再产生效果。
  Future<bool> handleUnauthorized({
    int? statusCode,
    String? message,
    String? expectedToken,
    int? expectedRevision,
  }) async {
    final targetToken = expectedToken ?? tokenSession.getToken();
    if (targetToken == null) {
      return expectedToken == null;
    }
    if (expectedRevision != null && tokenSession.revision != expectedRevision) {
      return false;
    }

    final inFlight = _unauthorizedOperation;
    if (inFlight != null) {
      final sameRequest =
          _unauthorizedToken == targetToken &&
          _unauthorizedRevision == expectedRevision;
      final handled = await inFlight;
      if (sameRequest) {
        return handled;
      }
      return handleUnauthorized(
        statusCode: statusCode,
        message: message,
        expectedToken: targetToken,
        expectedRevision: expectedRevision,
      );
    }

    if (!tokenSession.isCurrentToken(targetToken) ||
        (expectedRevision != null &&
            tokenSession.revision != expectedRevision)) {
      return false;
    }

    final operation = _clearTokenAndNotify(
      targetToken,
      expectedRevision,
      statusCode,
      message,
    );
    _unauthorizedOperation = operation;
    _unauthorizedToken = targetToken;
    _unauthorizedRevision = expectedRevision;
    try {
      return await operation;
    } finally {
      if (identical(_unauthorizedOperation, operation)) {
        _unauthorizedOperation = null;
        _unauthorizedToken = null;
        _unauthorizedRevision = null;
      }
    }
  }

  void reportError(String message) => onError?.call(message);

  void log(
    KoiApiLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    onLog?.call(level, message, error, stackTrace);
  }

  Future<bool> _clearTokenAndNotify(
    String expectedToken,
    int? expectedRevision,
    int? statusCode,
    String? message,
  ) async {
    if (!tokenSession.isCurrentToken(expectedToken) ||
        (expectedRevision != null &&
            tokenSession.revision != expectedRevision)) {
      return false;
    }

    Object? clearError;
    StackTrace? clearStackTrace;
    var revoked = false;
    final revocationRevision = tokenSession.revision + 1;
    try {
      revoked = await tokenSession.clearTokenIfCurrent(expectedToken);
    } catch (error, stackTrace) {
      revoked = true;
      clearError = error;
      clearStackTrace = stackTrace;
      log(
        KoiApiLogLevel.error,
        'Failed to clear persisted authentication token',
        error,
        stackTrace,
      );
    }

    if (!revoked) {
      return false;
    }

    if (tokenSession.revision != revocationRevision) {
      if (clearError != null) {
        Error.throwWithStackTrace(clearError, clearStackTrace!);
      }
      return false;
    }

    await onUnauthorized?.call(statusCode, message);

    if (clearError != null) {
      Error.throwWithStackTrace(clearError, clearStackTrace!);
    }
    return true;
  }
}
