import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';

/// Web keeps the token in memory only: browser storage is readable by any
/// script on the page, so a refresh simply starts a new login.
Future<KoiTokenSession> loadDefaultTokenSession() async {
  return KoiMemoryTokenSession();
}
