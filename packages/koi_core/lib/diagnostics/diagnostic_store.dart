import 'dart:async';
import 'dart:convert';

import 'package:koi_core/logging/app_logger.dart';

final class DiagnosticEvent {
  const DiagnosticEvent({
    required this.id,
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stack,
  });
  final int id;
  final DateTime time;
  final AppLogLevel level;
  final String source;
  final String message;
  final String? error;
  final String? stack;
  Map<String, Object?> toJson() => {
    'id': id,
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'source': source,
    'message': message,
    'error': error,
    'stack': stack,
  };
  factory DiagnosticEvent.fromJson(Map<String, Object?> json) =>
      DiagnosticEvent(
        id: json['id'] as int,
        time: DateTime.parse(json['time'] as String),
        level: AppLogLevel.values.byName(json['level'] as String),
        source: json['source'] as String,
        message: json['message'] as String,
        error: json['error'] as String?,
        stack: json['stack'] as String?,
      );
}

final class DiagnosticQuery {
  const DiagnosticQuery({this.level, this.source, this.text = ''});
  final AppLogLevel? level;
  final String? source;
  final String text;
  bool matches(DiagnosticEvent event) =>
      (level == null || level == event.level) &&
      (source == null || source == event.source) &&
      '${event.message}\n${event.error ?? ''}\n${event.stack ?? ''}'
          .toLowerCase()
          .contains(text.toLowerCase());
}

final class DiagnosticPage {
  const DiagnosticPage(this.items, this.nextCursor, this.revision);
  final List<DiagnosticEvent> items;
  final int? nextCursor;
  final int revision;
}

abstract interface class DiagnosticStore {
  DiagnosticPage query(DiagnosticQuery query, {int? cursor, int limit = 100});
  DiagnosticEvent? readDetail(int id);
  Stream<int> watchChanges();
  Stream<List<int>> exportSnapshot([
    DiagnosticQuery query = const DiagnosticQuery(),
  ]);
  Future<void> close();
}

typedef DiagnosticPersistence = Future<void> Function(
  List<DiagnosticEvent> events,
);

/// Bounded diagnostics; persistence failure is observable and never logged recursively.
final class BoundedDiagnosticStore implements DiagnosticStore {
  BoundedDiagnosticStore({
    this.maxBytes = 6 * 1024 * 1024,
    this.persist,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxBytes < 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
  }
  final int maxBytes;
  final DiagnosticPersistence? persist;
  Future<void> Function()? onClose;
  final DateTime Function() _clock;
  final _events = <DiagnosticEvent>[];
  final _sizes = <int>[];
  final _changes = StreamController<int>.broadcast(sync: true);
  int _revision = 0;
  int _notification = 0;
  int _bytes = 0;
  bool _closed = false;
  bool _persistDirty = false;
  Future<void>? _persisting;
  Object? persistenceError;
  int get byteLength => _bytes;
  int get revision => _revision;

  void restore(Iterable<DiagnosticEvent> events) {
    if (_events.isNotEmpty || _revision != 0) {
      throw StateError('Restore only into an empty store');
    }
    for (final event in events) {
      if (event.id <= _revision) {
        throw const FormatException('Log IDs must increase');
      }
      _append(event);
      _revision = event.id;
    }
  }

  void record(
    AppLogLevel level,
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_closed) {
      return;
    }
    final event = DiagnosticEvent(
      id: ++_revision,
      time: _clock().toUtc(),
      level: level,
      source: source,
      message: redactDiagnostic(message),
      error: error == null ? null : redactDiagnostic('$error'),
      stack: stackTrace == null ? null : redactDiagnostic('$stackTrace'),
    );
    _append(event);
    _changes.add(++_notification);
    _schedulePersistence();
  }

  void _append(DiagnosticEvent event) {
    final size = utf8.encode(jsonEncode(event.toJson())).length + 1;
    // Never retain an unbounded exceptional event, nor silently truncate an export.
    if (size > maxBytes) {
      event = DiagnosticEvent(
        id: event.id,
        time: event.time,
        level: AppLogLevel.warning,
        source: 'diagnostics',
        message: 'Record exceeded diagnostic capacity ($size bytes).',
      );
    }
    final storedSize = utf8.encode(jsonEncode(event.toJson())).length + 1;
    _events.add(event);
    _sizes.add(storedSize);
    _bytes += storedSize;
    while (_bytes > maxBytes && _events.isNotEmpty) {
      _bytes -= _sizes.removeAt(0);
      _events.removeAt(0);
    }
  }

  void _schedulePersistence() {
    if (persist == null) {
      return;
    }
    _persistDirty = true;
    _persisting ??= _flushPersistence();
  }

  Future<void> _flushPersistence() async {
    // Queue a microtask so synchronous log bursts coalesce before copying.
    await Future<void>.value();
    while (_persistDirty) {
      _persistDirty = false;
      final previousError = persistenceError;
      try {
        await persist!(List.unmodifiable(_events));
        persistenceError = null;
      } catch (error) {
        persistenceError = error;
      }
      if (previousError != persistenceError && !_changes.isClosed) {
        _changes.add(++_notification);
      }
    }
    _persisting = null;
  }

  @override
  DiagnosticPage query(DiagnosticQuery query, {int? cursor, int limit = 100}) {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit');
    }
    final matching = _events.reversed.where(
      (e) => (cursor == null || e.id < cursor) && query.matches(e),
    );
    final page = matching.take(limit + 1).toList();
    final hasMore = page.length > limit;
    if (hasMore) {
      page.removeLast();
    }
    return DiagnosticPage(
      List.unmodifiable(page),
      hasMore ? page.last.id : null,
      _revision,
    );
  }

  @override
  DiagnosticEvent? readDetail(int id) {
    for (final event in _events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  @override
  Stream<int> watchChanges() => _changes.stream;
  @override
  Stream<List<int>> exportSnapshot([
    DiagnosticQuery query = const DiagnosticQuery(),
  ]) {
    // Capture now, not at the stream's first listen/await.
    final snapshot = List<DiagnosticEvent>.unmodifiable(
      _events.where(query.matches),
    );
    return Stream.fromIterable(
      snapshot.map((event) => utf8.encode('${jsonEncode(event.toJson())}\n')),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _persisting;
    await _changes.close();
    await onClose?.call();
  }
}

/// Credentials are removed before every sink and persisted snapshot.
String redactDiagnostic(String value) => value
    .replaceAllMapped(
      RegExp(
        r'''((?:authorization|cookie|set-cookie)["\']?\s*[:=]\s*["\']?)(?:(?:bearer|basic)\s+)?[^\r\n"\',;]+''',
        caseSensitive: false,
      ),
      (m) => '${m[1]}[redacted]',
    )
    .replaceAllMapped(
      RegExp(
        r'''((?:access_token|refresh_token|password|api_key|secret)["\']?\s*[=:]\s*["\']?)[^\s"\'&,;]+''',
        caseSensitive: false,
      ),
      (m) => '${m[1]}[redacted]',
    );
