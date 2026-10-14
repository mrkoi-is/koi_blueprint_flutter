library;

import 'package:koi_api_bootstrap/src/backend/web_backend.dart'
    if (dart.library.io) 'package:koi_api_bootstrap/src/backend/native_backend.dart'
    as backend;
import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';
import 'package:koi_api_bootstrap/src/koi_api_bootstrap_options.dart';
import 'package:koi_api_bootstrap/src/koi_api_runtime.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';
import 'package:koi_api_bootstrap/src/token_storage/web_token_session.dart'
    if (dart.library.io) 'package:koi_api_bootstrap/src/token_storage/native_token_session.dart'
    as token_storage;

export 'src/koi_api_bindings.dart';
export 'src/koi_api_bootstrap_options.dart';
export 'src/koi_api_log.dart';
export 'src/koi_api_runtime.dart';
export 'src/koi_memory_token_session.dart';
export 'src/koi_secure_token_session.dart';

/// 初始化当前平台对应的 API 运行时。
///
/// 原生平台会初始化 `koi_network`。Web 使用明确的空操作运行时，确保导入此
/// 公共库时不会将仅支持原生平台的网络代码带入 Web 构建。
Future<KoiApiRuntime> bootstrapKoiApi(
  KoiApiBootstrapOptions options, {
  KoiApiBindings? bindings,
}) {
  return backend.bootstrapKoiApiBackend(options, bindings ?? KoiApiBindings());
}

/// 释放当前活动的 API 运行时（如果存在）。
Future<void> disposeKoiApi() => backend.disposeKoiApiBackend();

/// 创建当前平台默认的令牌会话。
///
/// 原生平台会将令牌保存在安全存储中，但调用方应用仍需在重启后验证令牌并恢复
/// 用户会话。Web 仅在内存中保存令牌，刷新页面后需要重新登录。具体存储实现不会
/// 暴露在公共 API 中。
Future<KoiTokenSession> createDefaultTokenSession() {
  return token_storage.loadDefaultTokenSession();
}
