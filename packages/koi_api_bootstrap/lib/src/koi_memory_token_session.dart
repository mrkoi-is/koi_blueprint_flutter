import 'dart:async';

abstract interface class KoiTokenSession {
  String? getToken();

  bool get hasToken;

  Future<void> saveToken(String token);

  Future<void> clearToken();
}

class KoiMemoryTokenSession implements KoiTokenSession {
  KoiMemoryTokenSession({String? initialToken}) : _token = initialToken;

  String? _token;

  @override
  String? getToken() => _token;

  @override
  bool get hasToken => _token?.isNotEmpty ?? false;

  @override
  Future<void> saveToken(String token) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token must not be empty');
    }
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }
}

/// 底层存储操作失败时，仍以拒绝请求认证的方式保护会话。
/// 在访问委托存储之前，会先同步撤销当前令牌。
class KoiRevocableTokenSession implements KoiTokenSession {
  KoiRevocableTokenSession(KoiTokenSession delegate)
    : _delegate = delegate,
      _token = delegate.getToken();

  final KoiTokenSession _delegate;
  String? _token;
  int _operation = 0;
  int _storageBusy = 0;
  bool _storageFailure = false;
  Future<void> _storageMutation = Future<void>.value();

  @override
  String? getToken() {
    if (_storageBusy == 0 && !_storageFailure) {
      final persistedToken = _delegate.getToken();
      if (persistedToken != _token) {
        _token = persistedToken;
      }
    }
    return _token;
  }

  @override
  bool get hasToken => getToken()?.isNotEmpty ?? false;

  int get revision => _operation;

  @override
  Future<void> saveToken(String token) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token must not be empty');
    }

    final operation = ++_operation;
    _token = null;
    try {
      await _mutateStorage(() => _delegate.saveToken(token));
      _storageFailure = false;
    } catch (_) {
      _storageFailure = true;
      rethrow;
    }
    if (operation == _operation) {
      _token = token;
    }
  }

  @override
  Future<void> clearToken() {
    ++_operation;
    _token = null;
    return _clearToken();
  }

  Future<void> _clearToken() async {
    try {
      await _mutateStorage(_delegate.clearToken);
      _storageFailure = false;
    } catch (_) {
      _storageFailure = true;
      rethrow;
    }
  }

  bool isCurrentToken(String token) => getToken() == token;

  Future<bool> clearTokenIfCurrent(String token) {
    if (!isCurrentToken(token)) {
      return Future<bool>.value(false);
    }

    ++_operation;
    _token = null;
    return _clearTokenIfCurrent();
  }

  Future<bool> _clearTokenIfCurrent() async {
    try {
      await _mutateStorage(_delegate.clearToken);
      _storageFailure = false;
      return true;
    } catch (_) {
      _storageFailure = true;
      rethrow;
    }
  }

  Future<T> _mutateStorage<T>(Future<T> Function() mutation) {
    final completer = Completer<T>();
    _storageBusy++;
    _storageMutation = _storageMutation.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _storageBusy--;
      }
    });
    return completer.future;
  }
}
