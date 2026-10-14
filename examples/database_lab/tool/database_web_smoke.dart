import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:database_lab/core/database/open_database_web.dart';
import 'package:database_lab/features/library/data/drift_library_repository.dart';
import 'package:database_lab/features/library/data/library_database.dart';
import 'package:drift/wasm.dart';
import 'package:web/web.dart' as web;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final name = 'koi_database_smoke_${DateTime.now().microsecondsSinceEpoch}';
  final checks = <String>[];
  final opened = <LibraryDatabase>[];
  String? mode;
  late Map<String, Object?> report;
  try {
    final response = await web.window.fetch('library_v1.sqlite'.toJS).toDart;
    if (!response.ok) throw StateError('Fixture HTTP ${response.status}');
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    Future<Uint8List?> initial() async => bytes;
    final failedHandle = await openWebDatabase(
      name: name,
      initializeDatabase: initial,
    );
    mode = failedHandle.availability.mode;
    check(
      failedHandle.availability.persistent &&
          failedHandle.availability.multiTabSafe,
      'A real, synchronized persistent implementation is required: $mode',
    );
    final failed = LibraryDatabase(
      failedHandle.executor,
      beforeMigrationCommit: () =>
          throw StateError('injected migration rollback'),
    );
    opened.add(failed);
    var rejected = false;
    try {
      await DriftLibraryRepository(failed).watch().first;
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'Injected migration must fail');
    await failed.close();
    opened.remove(failed);
    checks.add('v1 migration failure');

    final handle = await openWebDatabase(name: name);
    final first = LibraryDatabase(handle.executor);
    opened.add(first);
    final repo = DriftLibraryRepository(first);
    final legacy = await repo.watch().first;
    check(
      legacy.length == 2 && legacy.last.body == '旧正文必须保留',
      'Nonempty fixture survives failed migration and retry',
    );
    check(
      legacy.first.tags.join('|') == "quote'tag|tag,with,comma",
      'Join must preserve punctuation',
    );
    checks.add('v1→v2 migration, rollback recovery and join');
    final id = await repo.save(
      title: 'Web新建',
      body: 'WASM persistence',
      tags: ['test', 'shared'],
    );
    await first.close();
    opened.remove(first);

    final reopened = LibraryDatabase(
      (await openWebDatabase(name: name)).executor,
      beforeMigrationCommit: () => throw StateError('Migration ran twice'),
    );
    opened.add(reopened);
    final reopenedRepo = DriftLibraryRepository(reopened);
    check(
      (await reopenedRepo.watch().first).first.id == id,
      'Close and reopen must persist',
    );
    checks.add('close/reopen persistence and one-time migration');

    final second = LibraryDatabase(
      (await openWebDatabase(name: name)).executor,
    );
    opened.add(second);
    final secondRepo = DriftLibraryRepository(second);
    final notification = secondRepo
        .watch(archived: true)
        .firstWhere((notes) => notes.any((note) => note.id == id));
    await repoFor(reopened).setArchived(id, true);
    await notification.timeout(const Duration(seconds: 10));
    checks.add('two connections share committed watch updates');

    await reopened.customStatement(
      "CREATE TRIGGER reject_bad BEFORE INSERT ON library_document_tags WHEN NEW.tag_id IN (SELECT id FROM library_tags WHERE name='reject') BEGIN SELECT RAISE(ABORT, 'rollback'); END",
    );
    var rolledBack = false;
    try {
      await reopenedRepo.save(
        id: id,
        title: 'Do not commit',
        body: 'changed',
        tags: ['new', 'reject'],
      );
    } catch (_) {
      rolledBack = true;
    }
    final stable = (await secondRepo.watch(archived: true).first).single;
    check(
      rolledBack &&
          stable.title == 'Web新建' &&
          stable.tags.join('|') == 'shared|test',
      'Transaction restores document and relations',
    );
    checks.add('transaction rollback across document and tags');
    report = {'status': 'passed', 'mode': mode, 'checks': checks};
  } catch (error, stack) {
    report = {
      'status': 'failed',
      'mode': mode,
      'checks': checks,
      'error': '$error',
      'stack': '$stack',
    };
  } finally {
    for (final database in opened.reversed) {
      await database.close();
    }
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
      driftWorkerUri: Uri.base.resolve('drift_worker.dart.js'),
    );
    for (final existing in probe.existingDatabases.where(
      (entry) => entry.$2 == name,
    )) {
      await probe.deleteDatabase(existing);
    }
  }
  _report(report);
}

DriftLibraryRepository repoFor(LibraryDatabase database) =>
    DriftLibraryRepository(database);
void _report(Map<String, Object?> report) {
  final encoded = jsonEncode(report);
  web.document.body!.textContent = encoded;
  web.document.documentElement!.setAttribute('data-test-result', encoded);
}
