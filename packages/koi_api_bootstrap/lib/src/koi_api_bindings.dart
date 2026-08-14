import 'package:koi_api_bootstrap/src/koi_api_log.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

typedef KoiApiUnauthorizedCallback =
    Future<void> Function(int? statusCode, String? message);

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

  /// The canonical session used by both repositories and network adapters.
  /// Persisted storage passed to the constructor must not be used directly.
  final KoiRevocableTokenSession tokenSession;
  final KoiApiUnauthorizedCallback? onUnauthorized;
  final KoiApiErrorCallback? onError;
  final KoiApiLogCallback? onLog;

  Future<bool>? _unauthorizedOperation;
  String? _unauthorizedToken;
  int? _unauthorizedRevision;

  /// Clears the token and invokes the unauthorized callback once.
  ///
  /// Multiple interceptors can observe the same 401 response. Concurrent calls
  /// share one operation, and later calls become no-ops after the token clears.
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
