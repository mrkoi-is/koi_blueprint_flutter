@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/data/workspace_storage_web.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import '../features/workspace/data/fixtures/workspace_v1_fixture.dart';

Future<web.IDBDatabase> _connect(String name) async {
  final request = web.window.indexedDB.open(name);
  final done = Completer<web.IDBDatabase>();
  request.onsuccess = ((web.Event _) => done.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('open failed'),
  )).toJS;
  return done.future;
}

Future<void> _write(web.IDBDatabase db, String key, String value) async {
  final tx = db.transaction('metadata'.toJS, 'readwrite');
  final done = Completer<void>();
  tx.oncomplete = ((web.Event _) => done.complete()).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('aborted'),
  )).toJS;
  tx.objectStore('metadata').put(value.toJS, key.toJS);
  await done.future;
}

Future<String?> _read(web.IDBDatabase db, String key) async {
  final tx = db.transaction('metadata'.toJS, 'readonly');
  final request = tx.objectStore('metadata').get(key.toJS);
  final done = Completer<String?>();
  request.onsuccess = ((web.Event _) => done.complete(
    (request.result as JSString?)?.toDart,
  )).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('read failed'),
  )).toJS;
  return done.future;
}

void main() {
  for (final shouldAbort in [false, true]) {
    test(
      'real IndexedDB v1 migration ${shouldAbort ? 'abort preserves old values and retry succeeds' : 'commits once with backup and CAS'}',
      () async {
        final name = 'koi_migrate_${DateTime.now().microsecondsSinceEpoch}';
        final created = await openStorage(webDatabaseName: name);
        await created.close();
        final raw = await _connect(name);
        await _write(raw, 'workspace', workspaceV1Fixture);
        await _write(raw, 'workspace.backup', 'existing backup');
        var abort = shouldAbort;
        final owner = await openStorage(
          webDatabaseName: name,
          beforeSnapshotCommit: () {
            if (abort) throw StateError('injected transaction abort');
          },
        );
        try {
          await expectLater(
            openStorage(webDatabaseName: name),
            throwsA(isA<WorkspaceInUse>()),
          );
          if (abort) {
            await expectLater(owner.repository.load(), throwsStateError);
            expect(await _read(raw, 'workspace'), workspaceV1Fixture);
            expect(await _read(raw, 'workspace.backup'), 'existing backup');
            abort = false;
          }
          final snapshot = await owner.repository.load();
          expect(snapshot.schemaVersion, 2);
          expect(snapshot.jobs.first.currentAttempt, 0);
          expect(snapshot.documents.single.text, '保留正文');
          expect(owner.repository.persistedVersion, 8);
          expect(
            jsonDecode((await _read(raw, 'workspace'))!)['schemaVersion'],
            2,
          );
          expect(await _read(raw, 'workspace.backup'), workspaceV1Fixture);
          await owner.repository.load();
          expect(owner.repository.persistedVersion, 8);
          await expectLater(
            owner.repository.save(snapshot, expectedVersion: 7),
            throwsA(isA<WorkspaceConflict>()),
          );
        } finally {
          raw.close();
          await owner.close();
          web.window.indexedDB.deleteDatabase(name);
        }
      },
    );
  }
}
