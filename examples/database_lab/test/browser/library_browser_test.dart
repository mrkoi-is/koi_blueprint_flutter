@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:database_lab/core/database/open_database_web.dart';
import 'package:database_lab/features/library/data/library_database.dart';
import 'package:database_lab/features/library/data/drift_library_repository.dart';
import 'package:drift/wasm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real browser storage migrates a nonempty fixture, reopens and watches committed relationships', () async {
    final origin = Uri.parse(web.window.location.origin);
    final sqlite = origin.resolve('/fixtures/database_web/sqlite3.wasm');
    final worker = origin.resolve(
      '/fixtures/database_web/drift_worker.dart.js',
    );
    final response = await web.window
        .fetch(origin.resolve('/fixtures/library_v1.sqlite').toString().toJS)
        .toDart;
    if (!response.ok) throw StateError('Fixture HTTP ${response.status}');
    final fixture = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final name = 'koi_db_browser_${DateTime.now().microsecondsSinceEpoch}';
    final opened = <LibraryDatabase>[];
    try {
      final firstHandle = await openWebDatabase(
        name: name,
        sqlite3Uri: sqlite,
        workerUri: worker,
        initializeDatabase: () async => fixture,
      );
      expect(firstHandle.availability.persistent, isTrue);
      expect(firstHandle.availability.multiTabSafe, isTrue);
      final first = LibraryDatabase(firstHandle.executor);
      opened.add(first);
      final repository = DriftLibraryRepository(first);
      final old = await repository.watch().first;
      expect(old.length, 2);
      expect(old.last.body, '旧正文必须保留');
      await repository.save(
        title: 'Browser saved',
        body: 'durable',
        tags: ['quote\'tag', 'comma,tag'],
      );
      await first.close();
      opened.remove(first);
      final second = LibraryDatabase(
        (await openWebDatabase(
          name: name,
          sqlite3Uri: sqlite,
          workerUri: worker,
        )).executor,
      );
      opened.add(second);
      final repo = DriftLibraryRepository(second);
      final persisted = (await repo.watch(query: 'Browser saved').first).single;
      expect(persisted.tags, ['comma,tag', "quote'tag"]);
      final changed = repo
          .watch(query: 'Browser saved')
          .firstWhere(
            (docs) =>
                docs.single.body == 'edited' &&
                docs.single.tags.single == 'complete',
          );
      await repo.save(
        id: persisted.id,
        title: 'Browser saved',
        body: 'edited',
        tags: ['complete'],
      );
      await changed;
    } finally {
      for (final db in opened.reversed) {
        await db.close();
      }
      final probe = await WasmDatabase.probe(
        sqlite3Uri: sqlite,
        driftWorkerUri: worker,
      );
      for (final db in probe.existingDatabases.where(
        (entry) => entry.$2 == name,
      )) {
        await probe.deleteDatabase(db);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
