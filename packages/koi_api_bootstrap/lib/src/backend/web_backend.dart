import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';
import 'package:koi_api_bootstrap/src/koi_api_bootstrap_options.dart';
import 'package:koi_api_bootstrap/src/koi_api_runtime.dart';

_WebKoiApiRuntime? _activeRuntime;

Future<KoiApiRuntime> bootstrapKoiApiBackend(
  KoiApiBootstrapOptions _,
  KoiApiBindings bindings,
) async {
  await disposeKoiApiBackend();
  final runtime = _WebKoiApiRuntime(bindings);
  _activeRuntime = runtime;
  return runtime;
}

Future<void> disposeKoiApiBackend() async {
  _activeRuntime?._markDisposed();
  _activeRuntime = null;
}

final class _WebKoiApiRuntime implements KoiApiRuntime {
  _WebKoiApiRuntime(this.bindings);

  @override
  final KoiApiBindings bindings;

  bool _disposed = false;

  @override
  KoiApiBackend get backend => KoiApiBackend.webNoop;

  @override
  bool get isNoop => true;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (identical(_activeRuntime, this)) {
      await disposeKoiApiBackend();
    } else {
      _markDisposed();
    }
  }

  void _markDisposed() {
    _disposed = true;
  }
}
