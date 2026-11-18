import 'package:koi_core/koi_core.dart';
import 'package:talker/talker.dart';

/// Talker is the ingress; the host's bounded store remains the only history.
final class TalkerDiagnosticRecorder {
  TalkerDiagnosticRecorder(this.store) {
    _talker = Talker(
      settings: TalkerSettings(useHistory: false, useConsoleLogs: false),
      observer: _Observer(store),
    );
    _removeNetwork = Diagnostics.register(record);
  }
  final BoundedDiagnosticStore Function() store;
  late final Talker _talker;
  late final void Function() _removeNetwork;
  bool _closed = false;
  void record(
    AppLogLevel level,
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? network,
  }) {
    if (_closed) return;
    try {
      _talker.logCustom(
        _Record(
          level,
          redactDiagnostic(message),
          source,
          error == null ? null : redactDiagnostic('$error'),
          stackTrace,
          network,
        ),
      );
    } catch (_) {
      /* A diagnostic sink cannot break application work. */
    }
  }

  void close() {
    _closed = true;
    _removeNetwork();
  }
}

final class _Record extends TalkerLog {
  _Record(
    this.level,
    String message,
    this.source,
    this.failure,
    this.stack,
    this.network,
  ) : super(message);
  final AppLogLevel level;
  final String source;
  final String? failure;
  final StackTrace? stack;
  final Map<String, Object?>? network;
}

final class _Observer extends TalkerObserver {
  _Observer(this.store);
  final BoundedDiagnosticStore Function() store;
  @override
  void onLog(TalkerData log) {
    if (log is _Record) {
      store().record(
        log.level,
        log.message ?? '',
        source: log.source,
        error: log.failure,
        stackTrace: log.stack,
        network: log.network,
      );
    }
  }
}
