import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  test(
    'exports a complete fixed snapshot over 64KB with Unicode and filter',
    () async {
      final store = BoundedDiagnosticStore();
      addTearDown(store.close);
      final large = List.filled(30000, '鲤').join();
      store.record(AppLogLevel.info, large, source: 'network');
      final export = store.exportSnapshot(
        const DiagnosticQuery(source: 'network'),
      );
      store.record(AppLogLevel.info, 'later', source: 'network');
      final bytes = await export.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      expect(bytes.length, greaterThan(65536));
      final lines = utf8.decode(bytes).trim().split('\n');
      expect(lines, hasLength(1));
      expect((jsonDecode(lines.single) as Map)['message'], large);
    },
  );

  test(
    'cursor remains stable while newer records arrive and store is bounded',
    () async {
      final store = BoundedDiagnosticStore(maxBytes: 4096);
      addTearDown(store.close);
      for (var i = 0; i < 20; i++) {
        store.record(AppLogLevel.info, 'message $i');
      }
      final first = store.query(const DiagnosticQuery(), limit: 5);
      store.record(AppLogLevel.error, 'new');
      final second = store.query(
        const DiagnosticQuery(),
        cursor: first.nextCursor,
        limit: 5,
      );
      expect(
        first.items
            .map((e) => e.id)
            .toSet()
            .intersection(second.items.map((e) => e.id).toSet()),
        isEmpty,
      );
      expect(second.items.first.id, lessThan(first.items.last.id));
      for (var i = 0; i < 100; i++) {
        store.record(AppLogLevel.info, 'next $i');
      }
      expect(store.byteLength, lessThanOrEqualTo(4096));
      expect(store.readDetail(1), isNull);
    },
  );

  test(
    'persistence is serialized and close waits for the final snapshot',
    () async {
      final gate = Completer<void>();
      final snapshots = <List<DiagnosticEvent>>[];
      final store = BoundedDiagnosticStore(
        persist: (events) async {
          snapshots.add(events);
          if (snapshots.length == 1) await gate.future;
        },
      );
      store.record(AppLogLevel.info, 'one');
      await Future<void>.delayed(Duration.zero);
      store.record(AppLogLevel.info, 'two');
      var closed = false;
      final closing = store.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      gate.complete();
      await closing;
      expect(snapshots.last.map((e) => e.message), ['one', 'two']);
      store.record(AppLogLevel.info, 'ignored');
      expect(store.query(const DiagnosticQuery()).items, hasLength(2));
    },
  );

  test('persistence failure is observable without recursive records', () async {
    var attempts = 0;
    final store = BoundedDiagnosticStore(
      persist: (_) async {
        attempts++;
        throw StateError('disk');
      },
    );
    store.record(AppLogLevel.error, 'business failure');
    await store.close();
    expect(attempts, 1);
    expect(store.persistenceError, isA<StateError>());
    expect(store.query(const DiagnosticQuery()).items, hasLength(1));
  });

  test('redacts credentials before storage and does not truncate oversized records silently', () async {
    final store = BoundedDiagnosticStore(maxBytes: 1024);
    addTearDown(store.close);
    store.record(
      AppLogLevel.error,
      'Authorization: Bearer abc access_token=def&password=ghi',
    );
    final event = store.query(const DiagnosticQuery()).items.single;
    expect(event.message, isNot(contains('abc')));
    expect(event.message, isNot(contains('def')));
    expect(event.message, isNot(contains('ghi')));
    store.record(AppLogLevel.info, List.filled(2000, 'x').join());
    expect(
      store.query(const DiagnosticQuery()).items.first.message,
      contains('exceeded'),
    );
    expect(store.byteLength, lessThanOrEqualTo(1024));
  });

  test(
    'restore validates identity, query filters and build identity is data only',
    () async {
      final store = BoundedDiagnosticStore();
      addTearDown(store.close);
      store.restore([
        DiagnosticEvent(
          id: 7,
          time: DateTime.utc(2026),
          level: AppLogLevel.error,
          source: 'test',
          message: 'Hello',
        ),
      ]);
      store.record(AppLogLevel.warning, 'bye');
      expect(store.revision, 8);
      expect(
        store
            .query(
              const DiagnosticQuery(
                level: AppLogLevel.error,
                source: 'test',
                text: 'HELLO',
              ),
            )
            .items
            .single
            .id,
        7,
      );
      expect(
        () => store.query(const DiagnosticQuery(), limit: 0),
        throwsArgumentError,
      );
      expect(() => store.restore([]), throwsStateError);
      expect(
        const BuildInfo(source: 'abc', channel: 'preview').toJson()['source'],
        'abc',
      );
    },
  );
}
