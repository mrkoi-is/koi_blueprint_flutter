@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_web.dart';
import 'package:workbench_app/features/workspace/data/selected_source_cleanup_web.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

void main() {
  test(
    'selected file URL cleanup revokes the actual browser object URL',
    () async {
      final blob = web.Blob(['content'.toJS].toJS);
      final url = web.URL.createObjectURL(blob);
      expect((await web.window.fetch(url.toJS).toDart).ok, isTrue);
      releaseSelectedSource(url);
      await expectLater(web.window.fetch(url.toJS).toDart, throwsA(anything));
      releaseSelectedSource('regular.txt');
    },
  );
  test(
    'corrupt browser snapshot fails explicitly and preserves original content',
    () async {
      final name = 'koi_corrupt_${DateTime.now().microsecondsSinceEpoch}';
      final storage = await openStorage(webDatabaseName: name);
      final request = web.window.indexedDB.open(name);
      final opened = Completer<web.IDBDatabase>();
      request.onsuccess = ((web.Event event) {
        opened.complete(request.result as web.IDBDatabase);
      }).toJS;
      final database = await opened.future;
      try {
        final transaction = database.transaction('metadata'.toJS, 'readwrite');
        final done = Completer<void>();
        transaction.oncomplete = ((web.Event event) {
          done.complete();
        }).toJS;
        transaction
            .objectStore('metadata')
            .put('{broken'.toJS, 'workspace'.toJS);
        await done.future;
        await expectLater(
          storage.repository.load(),
          throwsA(isA<WorkspaceStorageException>()),
        );
        // A second load still fails; no fallback silently wiped the persisted bytes.
        await expectLater(
          storage.repository.load(),
          throwsA(isA<WorkspaceStorageException>()),
        );
      } finally {
        database.close();
        await storage.close();
        web.window.indexedDB.deleteDatabase(name);
      }
    },
  );

  test(
    'request failure when newer database exists is surfaced without hanging',
    () async {
      final name = 'koi_version_${DateTime.now().microsecondsSinceEpoch}';
      final request = web.window.indexedDB.open(name, 2);
      final opened = Completer<web.IDBDatabase>();
      request.onsuccess = ((web.Event event) {
        opened.complete(request.result as web.IDBDatabase);
      }).toJS;
      final database = await opened.future;
      database.close();
      await expectLater(
        openStorage(webDatabaseName: name),
        throwsA(isA<WorkspaceStorageException>()),
      );
      web.window.indexedDB.deleteDatabase(name);
    },
  );
  test(
    'IndexedDB persists snapshot and actual Blob across reopened connections',
    () async {
      final name = 'koi_test_${DateTime.now().microsecondsSinceEpoch}';
      var storage = await openStorage(webDatabaseName: name);
      try {
        const snapshot = WorkspaceSnapshot(
          documents: [WorkspaceDocument(id: 'd', title: '中文资料', text: '正文')],
        );
        await storage.repository.save(snapshot);
        final key = await storage.assetStore.stage(
          Stream.value([1, 2, 3, 4]),
          name: 'sample.mp4',
        );
        await storage.assetStore.commit(key);
        await storage.close();
        storage = await openStorage(webDatabaseName: name);
        expect(await storage.repository.load(), snapshot);
        expect(await storage.assetStore.readBytes(key), [1, 2, 3, 4]);
        final lease = await storage.openPreview(key);
        final response = await web.window.fetch(lease.uri.toJS).toDart;
        expect((await response.arrayBuffer().toDart).toDart.asUint8List(), [
          1,
          2,
          3,
          4,
        ]);
        await lease.dispose();
        await lease.dispose();
        await storage.assetStore.remove(key);
        await expectLater(
          storage.assetStore.readBytes(key),
          throwsA(isA<WorkspaceStorageException>()),
        );
      } finally {
        await storage.close();
        web.window.indexedDB.deleteDatabase(name);
      }
    },
  );
  test('abort and startup cleanup remove real staged browser data', () async {
    final name = 'koi_cleanup_${DateTime.now().microsecondsSinceEpoch}';
    final WorkspaceStorage storage = await openStorage(webDatabaseName: name);
    try {
      final key = await storage.assetStore.stage(
        Stream.value([7]),
        name: 'sample.png',
      );
      await storage.assetStore.abort(key);
      await expectLater(
        storage.assetStore.commit(key),
        throwsA(isA<WorkspaceStorageException>()),
      );
      final other = await storage.assetStore.stage(
        Stream.value([9]),
        name: 'other.png',
      );
      await storage.assetStore.cleanupStaging();
      await expectLater(
        storage.assetStore.commit(other),
        throwsA(isA<WorkspaceStorageException>()),
      );
    } finally {
      await storage.close();
      web.window.indexedDB.deleteDatabase(name);
    }
  });
}
