/// Native composition 入口，仅由平台适配层或 App bootstrap 导入。
///
/// 此入口的 factory 接受 Dio，用于构造生成 Client；不得从业务公共契约重导出，
/// 也不得由 presentation 直接消费。平台无关调用方使用 koi_api_bootstrap.dart。
library;

import 'package:koi_api_bootstrap/src/backend/native_backend.dart';
import 'package:koi_api_bootstrap/src/koi_api_runtime.dart';
import 'package:koi_network/koi_network.dart' show Dio;

/// 使用已注册、受会话保护的后端构造生成 Client。
///
/// Runtime 释放或被替换后，不可继续构造或使用其 Client。调用方应先取消/等待
/// 在途请求再释放 Runtime；返回值由调用方注入强类型仓库，不传播 Dio。
T buildKoiApiClient<T>(
  KoiApiRuntime runtime,
  String backendKey,
  T Function(Dio dio) factory,
) => buildNativeKoiApiClient(runtime, backendKey, factory);
