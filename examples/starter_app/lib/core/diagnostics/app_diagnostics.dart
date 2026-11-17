import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart';

/// Export is a host-injected IO boundary. Minimal apps have no exporter.
typedef DiagnosticsExporter = Future<String> Function(
  Stream<List<int>> snapshot,
);

/// Installed once by main, before business bootstrap. Pages only borrow its store.
final class AppDiagnostics {
  AppDiagnostics({BoundedDiagnosticStore? store})
    : store = store ?? BoundedDiagnosticStore();
  static final instance = AppDiagnostics();
  BoundedDiagnosticStore store;
  bool _installed = false;
  DiagnosticRecorder? recorder;
  Object? _recorderOwner;
  VoidCallback registerRecorder(DiagnosticRecorder next) {
    final owner = Object();
    _recorderOwner = owner;
    recorder = next;
    return () {
      if (!identical(_recorderOwner, owner)) return;
      _recorderOwner = null;
      recorder = null;
    };
  }

  void write(
    AppLogLevel level,
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? network,
  }) {
    final target = recorder ?? store.record;
    target(
      level,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      network: network,
    );
  }

  DebugPrintCallback? _previousDebugPrint;
  late final DebugPrintCallback _debugPrint = _handleDebugPrint;
  void _handleDebugPrint(String? message, {int? wrapWidth}) {
    if (message != null) {
      write(AppLogLevel.debug, message, source: 'debugPrint');
    }
  }

  DiagnosticsExporter? _exporter;
  Object? _exporterOwner;

  /// A stale feature disposer must not remove a newer installation's exporter.
  VoidCallback registerExporter(DiagnosticsExporter exporter) {
    final owner = Object();
    _exporterOwner = owner;
    _exporter = exporter;
    return () {
      if (!identical(_exporterOwner, owner)) return;
      _exporterOwner = null;
      _exporter = null;
    };
  }

  Future<String> exportSnapshot(Stream<List<int>> snapshot) async {
    final exporter = _exporter;
    if (exporter == null) {
      throw UnsupportedError('Diagnostic export is not installed');
    }
    return exporter(snapshot);
  }

  FlutterExceptionHandler? _previousFlutter;
  bool Function(Object, StackTrace)? _previousPlatform;
  AppLogSink? _previousSink;
  final _seen = HashSet<Object>.identity();
  Timer? _clearSeen;
  late final observer = DiagnosticObserver(this);
  late final FlutterExceptionHandler _flutter = _handleFlutter;
  void _handleFlutter(FlutterErrorDetails details) {
    record(details.exception, details.stack ?? StackTrace.current, 'flutter');
    _previousFlutter?.call(details);
  }

  late final bool Function(Object, StackTrace) _platform = _handlePlatform;
  bool _handlePlatform(Object error, StackTrace stack) {
    record(error, stack, 'platform');
    return _previousPlatform?.call(error, stack) ?? true;
  }

  late final AppLogSink _sink = _handleLog;
  void _handleLog(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (error == null) {
      write(level, message);
    } else {
      record(
        error,
        stackTrace ?? StackTrace.current,
        'app',
        message: message,
        level: level,
      );
    }
  }

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutter = FlutterError.onError;
    _previousPlatform = PlatformDispatcher.instance.onError;
    _previousSink = AppLogger.sink;
    FlutterError.onError = _flutter;
    PlatformDispatcher.instance.onError = _platform;
    AppLogger.sink = _sink;
    _previousDebugPrint = debugPrint;
    debugPrint = _debugPrint;
  }

  void record(
    Object error,
    StackTrace stack,
    String source, {
    String? message,
    AppLogLevel level = AppLogLevel.error,
  }) {
    if (!_seen.add(error)) return;
    _clearSeen ??= Timer(Duration.zero, () {
      _seen.clear();
      _clearSeen = null;
    });
    write(
      level,
      message ?? '$error',
      source: source,
      error: error,
      stackTrace: stack,
    );
  }

  Future<void> replaceStore(BoundedDiagnosticStore next) async {
    final old = store;
    next.importEvents(old.snapshot);
    store = next;
    await old.close();
  }

  Future<void> close() async {
    if (_installed) {
      if (identical(FlutterError.onError, _flutter)) {
        FlutterError.onError = _previousFlutter;
      }
      if (identical(PlatformDispatcher.instance.onError, _platform)) {
        PlatformDispatcher.instance.onError = _previousPlatform;
      }
      if (identical(AppLogger.sink, _sink)) AppLogger.sink = _previousSink;
    }
    if (identical(debugPrint, _debugPrint)) {
      debugPrint = _previousDebugPrint ?? debugPrintThrottled;
    }
    recorder = null;
    _installed = false;
    _exporterOwner = null;
    _exporter = null;
    _clearSeen?.cancel();
    _clearSeen = null;
    _seen.clear();
    await store.close();
  }
}

final class DiagnosticObserver extends ProviderObserver {
  DiagnosticObserver(this.runtime);
  final AppDiagnostics runtime;
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    runtime.record(error, stackTrace, context.provider.name ?? 'provider');
  }
}
