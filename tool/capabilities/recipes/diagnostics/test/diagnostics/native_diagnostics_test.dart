@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/data/persistent_diagnostics_native.dart';

void main() {
  test(
    'persistent Native log rotates, reopens and exports fixed Unicode snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('koi-diagnostics-');
      addTearDown(() => dir.delete(recursive: true));
      var store = await openDiagnosticStore(directory: dir);
      for (var i = 0; i < 65; i++) {
        store.record(
          AppLogLevel.info,
          '$i 鲤 ${'x' * 110000}',
          source: 'native',
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await store.close();
      final segments = await dir
          .list()
          .where((entry) => entry.path.endsWith('.ndjson'))
          .toList();
      expect(segments.length, greaterThan(1));
      var bytes = 0;
      for (final file in segments.cast<File>()) {
        bytes += await file.length();
      }
      expect(bytes, lessThanOrEqualTo(6 * 1024 * 1024));
      store = await openDiagnosticStore(directory: dir);
      final page = store.query(const DiagnosticQuery(source: 'native'));
      expect(page.items, isNotEmpty);
      expect(page.items.first.message, contains('鲤'));
      final snapshot = store.exportSnapshot();
      store.record(AppLogLevel.error, 'later');
      final export = await snapshot.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(utf8.decode(export), isNot(contains('later')));
      await store.close();
    },
  );

  test(
    'corrupt Native tail retains original and opens bounded fallback',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'koi-diagnostics-broken-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/events-00000001.ndjson');
      await file.writeAsString('{"incomplete": true');
      final original = await file.readAsBytes();
      final store = await openDiagnosticStore(directory: dir);
      expect(store.persistenceError, isA<FormatException>());
      store.record(AppLogLevel.error, 'business still works');
      expect(
        store.query(const DiagnosticQuery()).items.first.message,
        'business still works',
      );
      await store.close();
      expect(await file.readAsBytes(), original);
    },
  );
}
