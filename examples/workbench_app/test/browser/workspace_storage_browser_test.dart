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
  test('Web Lock excludes a separate worker and crashed owner releases automatically', () async {
    final name = 'koi_worker_${DateTime.now().microsecondsSinceEpoch}';
    final script =
        "navigator.locks.request('koi-workspace:$name', {ifAvailable:true}, lock => { self.postMessage(lock ? 'acquired' : 'busy'); return lock ? new Promise(() => {}) : undefined; });";
    final url = web.URL.createObjectURL(
      web.Blob(
        [script.toJS].toJS,
        web.BlobPropertyBag(type: 'text/javascript'),
      ),
    );
    Future<(web.Worker, String)> startWorker() async {
      final worker = web.Worker(url.toJS);
      final result = Completer<String>();
      worker.onmessage = ((web.MessageEvent event) => result.complete(
        (event.data as JSString).toDart,
      )).toJS;
      worker.onerror = ((web.Event event) => result.completeError(
        StateError('worker failed'),
      )).toJS;
      return (worker, await result.future.timeout(const Duration(seconds: 10)));
    }

    final first = await openStorage(webDatabaseName: name);
    web.Worker? owner;
    try {
      final (blockedWorker, state) = await startWorker();
      expect(state, 'busy');
      blockedWorker.terminate();
      await first.close();
      final (worker, acquired) = await startWorker();
      owner = worker;
      expect(acquired, 'acquired');
      await expectLater(
        openStorage(webDatabaseName: name),
        throwsA(isA<WorkspaceInUse>()),
      );
      worker.terminate();
      owner = null;
      // Termination releases the lock asynchronously; no timeout-based takeover.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        try {
          final reopened = await openStorage(webDatabaseName: name);
          await reopened.close();
          break;
        } on WorkspaceInUse {
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    } finally {
      owner?.terminate();
      await first.close();
      web.URL.revokeObjectURL(url);
      web.window.indexedDB.deleteDatabase(name);
    }
  });

  test('exclusive ownership rejects duplicate connection without clearing live Blob and can reopen', () async {
    final name = 'koi_owner_${DateTime.now().microsecondsSinceEpoch}';
    final first = await openStorage(webDatabaseName: name);
    try {
      await first.repository.save(
        const WorkspaceSnapshot(
          documents: [WorkspaceDocument(id: 'a', title: '中文资料')],
        ),
      );
      final key = await first.assetStore.stage(
        Stream.value([1, 2]),
        name: 'active.png',
      );
      await expectLater(
        openStorage(webDatabaseName: name),
        throwsA(isA<WorkspaceInUse>()),
      );
      await first.assetStore.commit(key);
      await first.close();
      final second = await openStorage(webDatabaseName: name);
      try {
        expect((await second.repository.load()).documents.single.title, '中文资料');
        expect(second.repository.persistedVersion, 1);
        expect(await second.assetStore.readBytes(key), [1, 2]);
        await expectLater(
          second.repository.save(const WorkspaceSnapshot(), expectedVersion: 0),
          throwsA(isA<WorkspaceConflict>()),
        );
        expect((await second.repository.load()).documents.single.title, '中文资料');
      } finally {
        await second.close();
      }
    } finally {
      await first.close();
      web.window.indexedDB.deleteDatabase(name);
    }
  });

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
