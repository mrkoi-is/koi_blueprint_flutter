import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

/// Web 仅在内存中保存令牌：页面上的任意脚本都能读取浏览器存储，
/// 因此刷新页面后会重新登录。
Future<KoiTokenSession> loadDefaultTokenSession() async {
  return KoiMemoryTokenSession();
}
