import 'dart:convert';
import 'dart:io';

import 'package:koi_core/koi_core.dart';
import 'package:path_provider/path_provider.dart';

/// The log is a separate, rebuildable six MiB ring of complete NDJSON files.
/// A failed append leaves an observable in-memory fallback; it never logs itself.
Future<BoundedDiagnosticStore> openDiagnosticStore({
  Directory? directory,
}) async {
  final root =
      directory ??
      Directory('${(await getApplicationSupportDirectory()).path}/diagnostics');
  await root.create(recursive: true);
  final writer = _RotatingLog(root);
  late final List<DiagnosticEvent> records;
  try {
    records = await writer.restore();
  } catch (error) {
    final fallback = BoundedDiagnosticStore();
    fallback.persistenceError = error;
    fallback.record(
      AppLogLevel.warning,
      'Previous diagnostic log could not be restored',
      error: error,
    );
    return fallback;
  }
  final store = BoundedDiagnosticStore(persist: writer.write);
  try {
    store.restore(records);
  } catch (error) {
    store.record(
      AppLogLevel.warning,
      'Previous diagnostic log could not be restored',
      error: error,
    );
  }
  return store;
}

final class _RotatingLog {
  _RotatingLog(this.directory);
  final Directory directory;
  static const capacity = 6 * 1024 * 1024;
  static const segmentLimit = 1024 * 1024;
  int lastId = 0;
  int nextSegment = 1;
  File? current;

  Future<List<DiagnosticEvent>> restore() async {
    final files = await _files();
    final entries = <DiagnosticEvent>[];
    for (final file in files) {
      if (await file.length() > capacity) {
        throw const FormatException('Diagnostic segment exceeds capacity');
      }
      final bytes = await file.readAsBytes();
      // A partial last append is never interpreted as a successful event.
      final complete = bytes.lastIndexOf(10);
      if (bytes.isNotEmpty && complete != bytes.length - 1) {
        throw const FormatException(
          'Incomplete diagnostic append; original log retained',
        );
      }
      if (complete < 0) {
        continue;
      }
      final lines = const LineSplitter().convert(
        utf8.decode(bytes.sublist(0, complete + 1)),
      );
      for (final line in lines) {
        if (line.isEmpty) {
          continue;
        }
        final event = DiagnosticEvent.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );
        if (event.id <= lastId) {
          continue;
        }
        entries.add(event);
        lastId = event.id;
      }
    }
    if (files.isNotEmpty) {
      current = files.last;
      nextSegment =
          int.parse(files.last.uri.pathSegments.last.substring(7, 15)) + 1;
    }
    return entries;
  }

  Future<List<File>> _files() async {
    final files = await directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'^events-[0-9]{8}\.ndjson$')
                  .hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> write(List<DiagnosticEvent> events) async {
    final pending = events.where((event) => event.id > lastId).toList();
    if (pending.isEmpty) {
      return;
    }
    final lines = pending.map((event) => jsonEncode(event.toJson())).join('\n');
    final data = utf8.encode('$lines\n');
    if (data.length > capacity) {
      throw StateError('Diagnostic batch exceeds capacity');
    }
    var target = current;
    if (target == null ||
        (await target.length()) + data.length > segmentLimit) {
      target = File(
        '${directory.path}/events-${nextSegment.toString().padLeft(8, '0')}.ndjson',
      );
      nextSegment++;
      current = target;
    }
    final handle = await target.open(mode: FileMode.append);
    try {
      await handle.writeFrom(data);
      await handle.flush();
    } finally {
      await handle.close();
    }
    lastId = pending.last.id;
    final files = await _files();
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    for (final file in files) {
      if (total <= capacity || file.path == current?.path) {
        break;
      }
      final size = await file.length();
      await file.delete();
      total -= size;
    }
  }
}

Future<String> exportDiagnostics(Stream<List<int>> bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(
    '${directory.path}/diagnostics-${DateTime.now().toUtc().microsecondsSinceEpoch}.ndjson',
  );
  final output = file.openWrite();
  try {
    await output.addStream(bytes);
    await output.flush();
  } finally {
    await output.close();
  }
  return file.path;
}
