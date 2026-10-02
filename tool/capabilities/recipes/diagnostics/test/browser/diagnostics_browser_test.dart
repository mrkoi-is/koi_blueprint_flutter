@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/data/persistent_diagnostics_web.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'real IndexedDB persists and exports a fixed Unicode revision',
    () async {
      final name = 'diagnostics-test-${DateTime.now().microsecondsSinceEpoch}';
      var store = await openDiagnosticStore(databaseName: name);
      final message = '鲤🐟' * 16000;
      store.record(AppLogLevel.info, message, source: 'browser');
      await store.close();
      store = await openDiagnosticStore(databaseName: name);
      expect(
        store
            .query(const DiagnosticQuery(source: 'browser'))
            .items
            .single
            .message,
        message,
      );
      final snapshot = store.exportSnapshot();
      store.record(AppLogLevel.error, 'after export started');
      final bytes = await snapshot.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      expect(bytes.length, greaterThan(65536));
      expect(utf8.decode(bytes), isNot(contains('after export started')));
      await store.close();
    },
  );

  test(
    'damaged IndexedDB row is retained while diagnostics degrades',
    () async {
      final name =
          'diagnostics-corrupt-${DateTime.now().microsecondsSinceEpoch}';
      final initial = await openDiagnosticStore(databaseName: name);
      await initial.close();
      var database =
          await request(web.window.indexedDB.open(name, 1)) as web.IDBDatabase;
      var transaction = database.transaction('logs'.toJS, 'readwrite');
      var done = completed(transaction);
      transaction.objectStore('logs').put('broken-json'.toJS, 'events'.toJS);
      await done;
      database.close();

      final fallback = await openDiagnosticStore(databaseName: name);
      expect(fallback.persistenceError, isA<FormatException>());
      fallback.record(AppLogLevel.info, 'available in memory');
      await fallback.close();

      database =
          await request(web.window.indexedDB.open(name, 1)) as web.IDBDatabase;
      transaction = database.transaction('logs'.toJS, 'readonly');
      done = completed(transaction);
      final original = await request(
        transaction.objectStore('logs').get('events'.toJS),
      );
      await done;
      expect((original as JSString).toDart, 'broken-json');
      database.close();
    },
  );
}
