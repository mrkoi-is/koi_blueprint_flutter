import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/data/persistent_diagnostics_native.dart'
    if (dart.library.js_interop) 'package:__APP_PACKAGE__/features/diagnostics/data/persistent_diagnostics_web.dart'
    as platform;

Future<void> initializePersistentDiagnostics({
  Future<BoundedDiagnosticStore> Function()? openStore,
  DiagnosticsExporter? exporter,
}) async {
  if (_initialized) return;
  final pending = _initialization;
  if (pending != null) return pending;
  final operation = _initialize(openStore, exporter);
  _initialization = operation;
  try {
    await operation;
  } finally {
    if (identical(_initialization, operation)) _initialization = null;
  }
}

Future<void> _initialize(
  Future<BoundedDiagnosticStore> Function()? openStore,
  DiagnosticsExporter? exporter,
) async {
  final store = await (openStore ?? platform.openDiagnosticStore)();
  await AppDiagnostics.instance.replaceStore(store);
  _removeExporter = AppDiagnostics.instance.registerExporter(
    exporter ?? platform.exportDiagnostics,
  );
  _initialized = true;
}

bool _initialized = false;
Future<void>? _initialization;
void Function()? _removeExporter;

Future<void> disposePersistentDiagnostics() async {
  final pending = _initialization;
  if (pending != null) {
    try {
      await pending;
    } catch (_) {
      // A failed initialization never registered an exporter.
      return;
    }
  }
  if (!_initialized) return;
  _initialized = false;
  _removeExporter?.call();
  _removeExporter = null;
  await AppDiagnostics.instance.replaceStore(BoundedDiagnosticStore());
}
