import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:database_lab/core/database/open_database_native.dart';
import 'package:database_lab/features/library/data/library_database.dart';
import 'package:database_lab/features/library/data/drift_library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual SQLite background 10k relational library benchmark', () async {
    final directory = await Directory.systemTemp.createTemp('koi-db-perf-');
    final file = File('${directory.path}/library.sqlite');
    final database = LibraryDatabase(openNativeDatabase(file).executor);
    final rssBefore = ProcessInfo.currentRss;
    var rssPeak = rssBefore;
    final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (ProcessInfo.currentRss > rssPeak) rssPeak = ProcessInfo.currentRss;
    });
    try {
      await database.customSelect('SELECT 1').get();
      final watch = Stopwatch()..start();
      await database.transaction(() async {
        await database.batch((batch) {
          batch.insertAll(
            database.libraryDocuments,
            List.generate(
              10000,
              (i) => LibraryDocumentsCompanion.insert(
                title: 'Document $i',
                body: List.filled(256, 'x').join(),
              ),
            ),
          );
          batch.insertAll(
            database.libraryTags,
            List.generate(
              20,
              (i) => LibraryTagsCompanion.insert(name: 'Tag $i'),
            ),
          );
          batch.insertAll(
            database.libraryDocumentTags,
            List.generate(
              10000,
              (i) => LibraryDocumentTagsCompanion.insert(
                documentId: i + 1,
                tagId: i % 20 + 1,
              ),
            ),
          );
        });
      });
      final insertMs = watch.elapsedMicroseconds / 1000;
      final repository = DriftLibraryRepository(database);
      watch.reset();
      final all = await repository.watch().first;
      final allMs = watch.elapsedMicroseconds / 1000;
      expect(all.length, 10000);
      expect(all.every((doc) => doc.tags.length == 1), true);
      watch.reset();
      final filtered = await repository.watch(query: '9999').first;
      final searchMs = watch.elapsedMicroseconds / 1000;
      expect(filtered.length, 1);
      final changed = Completer<void>();
      var notifications = 0;
      final subscription = repository.watch(query: '9999').listen((docs) {
        notifications++;
        if (docs.single.tags.contains('Changed') && !changed.isCompleted) {
          changed.complete();
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      watch.reset();
      await repository.save(
        id: 10000,
        title: 'Document 9999',
        body: 'updated',
        tags: ['Changed'],
      );
      await changed.future;
      final watchMs = watch.elapsedMicroseconds / 1000;
      await subscription.cancel();
      final report = {
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
        'runtime': 'Flutter test VM, NativeDatabase.createInBackground, real SQLite file',
        'documents': 10000,
        'relationships': 10000,
        'bodyCharactersPerDocument': 256,
        'batchTransactionMs': insertMs,
        'fullRelationalReadMs': allMs,
        'filteredRelationalReadMs': searchMs,
        'transactionToWatchMs': watchMs,
        'watchNotifications': notifications,
        'databaseBytes': await file.length(),
        'rss': {
          'beforeBytes': rssBefore,
          'afterBytes': ProcessInfo.currentRss,
          'sampledPeakBytes': rssPeak,
        },
        'frameTime': 'NOT_MEASURED_IN_VM',
      };
      final output = File('build/perf/database-native.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // ignore: avoid_print
      print(jsonEncode(report));
    } finally {
      sampler.cancel();
      await database.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
