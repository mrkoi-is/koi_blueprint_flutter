import 'package:koi_diagnostics/koi_diagnostics.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';

TalkerDiagnosticRecorder? _recorder;
DiagnosticLan? _lan;
void Function()? _removeRecorder;
DiagnosticLan? get diagnosticLan => _lan;
void installTalkerDiagnostics() {
  if (_recorder != null) return;
  final runtime = AppDiagnostics.instance;
  _recorder = TalkerDiagnosticRecorder(() => runtime.store);
  _removeRecorder = runtime.registerRecorder(_recorder!.record);
  _lan = DiagnosticLan(() => runtime.store);
}

Future<void> uninstallTalkerDiagnostics() async {
  await _lan?.close();
  _lan = null;
  _removeRecorder?.call();
  _removeRecorder = null;
  _recorder?.close();
  _recorder = null;
}
