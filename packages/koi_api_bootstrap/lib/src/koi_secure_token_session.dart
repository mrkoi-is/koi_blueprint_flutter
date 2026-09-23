import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

/// 用于持久化认证令牌的最小键值存储接口。
///
/// 具体存储插件不会暴露在公共 API 中，测试也可以替换为模拟实现。
abstract interface class KoiTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> delete();
}

/// 通过 [KoiTokenStore] 持久化认证令牌，并使用 [load] 预加载到内存中的副本
/// 支持同步读取。
class KoiSecureTokenSession implements KoiTokenSession {
  KoiSecureTokenSession._(this._store, this._token);

  final KoiTokenStore _store;
  String? _token;

  /// 读取一次持久化令牌，以便 [getToken] 保持同步。
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
