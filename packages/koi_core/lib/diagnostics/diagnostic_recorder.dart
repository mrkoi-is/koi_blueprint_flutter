import 'dart:convert';
import 'dart:math';

import 'package:koi_core/diagnostics/diagnostic_store.dart';
import 'package:koi_core/logging/app_logger.dart';

/// A recorder never borrows mutable HTTP objects. Its inputs are safe snapshots.
typedef DiagnosticRecorder = void Function(
  AppLogLevel level,
  String message, {
  String source,
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?>? network,
});

abstract final class Diagnostics {
  static final _recorders = <({Object owner, DiagnosticRecorder recorder})>[];
  static DiagnosticRecorder? get _target => _recorders.lastOrNull?.recorder;
  static void Function() register(DiagnosticRecorder recorder) {
    final owner = Object();
    _recorders.add((owner: owner, recorder: recorder));
    return () =>
        _recorders.removeWhere((entry) => identical(entry.owner, owner));
  }

  static DiagnosticTrace? startNetwork(
    String method,
    Uri uri, {
    Object? headers,
    Object? body,
    String? requestId,
    int attempt = 1,
  }) {
    final target = _target;
    if (target == null) return null;
    return DiagnosticTrace._(
      target,
      method,
      uri,
      headers,
      body,
      requestId,
      attempt,
    );
  }
}

/// Snapshot redaction happens before Talker, persistence, export and remote UI.
Object? diagnosticSnapshot(Object? value) => _Snapshot().capture(value, 0);

final class _Snapshot {
  int remaining = 65536;
  Object? capture(Object? value, int depth) {
    if (depth > 12) return '[depth limit]';
    if (remaining <= 0) return '[truncated]';
    remaining -= 16;
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries.take(200)) {
        if (remaining <= 0) {
          result['[truncated]'] = true;
          break;
        }
        final key = '${entry.key}';
        remaining -= key.length;
        result[key] =
            RegExp(
              r'authorization|cookie|token|password|secret|api.?key',
              caseSensitive: false,
            ).hasMatch(key)
            ? '[redacted]'
            : capture(entry.value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    if (value is Iterable && value is! String) {
      final result = <Object?>[];
      for (final item in value.take(200)) {
        if (remaining <= 0) {
          result.add('[truncated]');
          break;
        }
        result.add(capture(item, depth + 1));
      }
      return List<Object?>.unmodifiable(result);
    }
    if (value == null || value is num || value is bool) return value;
    final text = '$value';
    if (text.length <= 65536 &&
        (text.startsWith('{') || text.startsWith('['))) {
      try {
        return capture(jsonDecode(text), depth + 1);
      } catch (_) {
        /* Plain text. */
      }
    }
    final safe = redactDiagnostic(
      text.length > 65536 ? text.substring(0, 65536) : text,
    );
    final bytes = utf8.encode(safe);
    final limit = max(0, remaining);
    remaining -= bytes.length;
    return bytes.length <= limit
        ? safe
        : '${utf8.decode(bytes.take(limit).toList(), allowMalformed: true)}\n[truncated]';
  }
}

String diagnosticUrl(Uri uri) {
  final query = <String, dynamic>{};
  for (final e in uri.queryParametersAll.entries) {
    query[e.key] =
        RegExp(
          r'token|password|secret|api.?key|authorization|cookie',
          caseSensitive: false,
        ).hasMatch(e.key)
        ? '[redacted]'
        : e.value;
  }
  return uri
      .replace(userInfo: '', queryParameters: query.isEmpty ? null : query)
      .toString();
}

final class DiagnosticTrace {
  DiagnosticTrace._(
    this._record,
    String method,
    Uri uri,
    Object? headers,
    Object? body,
    String? requestId,
    int attempt,
  ) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _data = {
      'id': id,
      'requestId': requestId ?? id,
      'attempt': attempt,
      'method': method,
      'url': diagnosticUrl(uri),
      'requestHeaders': diagnosticSnapshot(headers),
      'requestBody': diagnosticSnapshot(body),
      'state': 'pending',
    };
    _emit();
  }
  final DiagnosticRecorder _record;
  final _watch = Stopwatch()..start();
  late Map<String, Object?> _data;
  bool _done = false;
  void response(int? status, Object? headers, {Object? body}) {
    if (_done) return;
    _data = {
      ..._data,
      'status': status,
      'responseHeaders': diagnosticSnapshot(headers),
      'responseBody': diagnosticSnapshot(body),
      'headersMs': _watch.elapsedMilliseconds,
      'state': 'receiving',
    };
    _emit();
  }

  void finish({Object? body, Object? error, bool cancelled = false}) {
    if (_done) return;
    _done = true;
    _data = {
      ..._data,
      if (body != null) 'responseBody': diagnosticSnapshot(body),
      'state': cancelled
          ? 'cancelled'
          : error != null
          ? 'failed'
          : 'complete',
      'durationMs': _watch.elapsedMilliseconds,
      if (error != null) 'error': diagnosticSnapshot(error),
    };
    _emit();
  }

  void _emit() {
    try {
      _record(
        _data['state'] == 'failed' ? AppLogLevel.error : AppLogLevel.info,
        '${_data['method']} ${_data['url']}',
        source: 'network',
        network: Map.unmodifiable(_data),
      );
    } catch (_) {
      /* Diagnostics must never change a request's behavior. */
    }
  }
}
