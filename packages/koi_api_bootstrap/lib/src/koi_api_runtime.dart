import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';

enum KoiApiBackend { native, webNoop }

abstract interface class KoiApiRuntime {
  KoiApiBackend get backend;
  KoiApiBindings get bindings;
  bool get isNoop;

  /// 本次装配声明的后端名称；Web no-op 仅保留声明，不提供网络能力。
  Set<String> get backendKeys;

  Future<void> dispose();
}
