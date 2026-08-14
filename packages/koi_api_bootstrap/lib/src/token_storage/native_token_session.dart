import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';
import 'package:koi_api_bootstrap/src/koi_secure_token_session.dart';

const _tokenStorageKey = 'koi_api_auth_token';

/// Persists the token in the platform secure storage (Keychain / Keystore)
/// so a restart keeps the session.
Future<KoiTokenSession> loadDefaultTokenSession() {
  return KoiSecureTokenSession.load(
    _FlutterSecureTokenStore(const FlutterSecureStorage()),
  );
}

final class _FlutterSecureTokenStore implements KoiTokenStore {
  _FlutterSecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenStorageKey);

  @override
  Future<void> write(String token) {
    return _storage.write(key: _tokenStorageKey, value: token);
  }

  @override
  Future<void> delete() => _storage.delete(key: _tokenStorageKey);
}
