import 'dart:developer' as developer;

enum AppLogLevel { debug, info, warning, error }

typedef AppLogSink =
    void Function(
      AppLogLevel level,
      String message, {
      Object? error,
      StackTrace? stackTrace,
    });

/// 零依赖日志门面：默认输出到 `dart:developer`，测试可替换 [sink] 捕获记录。
abstract final class AppLogger {
  static AppLogSink _sink = _developerSink;

  /// 替换日志输出口；传 `null` 恢复默认的 `developer.log`。
  static set sink(AppLogSink? sink) {
    _sink = sink ?? _developerSink;
  }

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    log(AppLogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    log(AppLogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    log(AppLogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    log(AppLogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  static void log(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _sink(level, message, error: error, stackTrace: stackTrace);
  }

  static void _developerSink(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'koi.${level.name}',
      level: level.severity,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

extension on AppLogLevel {
  int get severity => switch (this) {
    AppLogLevel.debug => 500,
    AppLogLevel.info => 800,
    AppLogLevel.warning => 900,
    AppLogLevel.error => 1000,
  };
}
