import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';

export 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart'
    show DiagnosticsExporter;

/// The host owns platform installation; this use case only borrows its port.
Future<String> exportDiagnostics(Stream<List<int>> snapshot) =>
    AppDiagnostics.instance.exportSnapshot(snapshot);
