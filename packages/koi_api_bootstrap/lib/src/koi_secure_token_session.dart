import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

/// Minimal key-value store used to persist the auth token.
///
/// Keeps the concrete storage plugin out of the public API and lets tests
/// substitute a fake.
abstract interface class KoiTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> delete();
}

/// Persists the auth token through a [KoiTokenStore] while serving
/// synchronous reads from an in-memory copy hydrated by [load].
class KoiSecureTokenSession implements KoiTokenSession {
  KoiSecureTokenSession._(this._store, this._token);

  final KoiTokenStore _store;
  String? _token;

  /// Reads the persisted token once so [getToken] can stay synchronous.
  static Future<KoiSecureTokenSession> load(KoiTokenStore store) async {
    final persisted = await store.read();
    return KoiSecureTokenSession._(
      store,
      persisted == null || persisted.isEmpty ? null : persisted,
    );
  }

  @override
  String? getToken() => _token;

  @override
  bool get hasToken => _token?.isNotEmpty ?? false;

  @override
  Future<void> saveToken(String token) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token must not be empty');
    }
    await _store.write(token);
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    await _store.delete();
    _token = null;
  }
}
