import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';

enum KoiApiBackend { native, webNoop }

abstract interface class KoiApiRuntime {
  KoiApiBackend get backend;
  KoiApiBindings get bindings;
  bool get isNoop;

  Future<void> dispose();
}
