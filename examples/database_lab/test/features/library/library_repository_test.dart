@TestOn('vm')
library;

import 'dart:io';

import 'package:database_lab/core/database/open_database_native.dart';
import 'package:database_lab/features/library/data/drift_library_repository.dart';
import 'package:database_lab/features/library/data/library_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late LibraryDatabase database;
  late DriftLibraryRepository repository;
  var memoryClosed = false;
  setUp(() {
    memoryClosed = false;
    database = LibraryDatabase(NativeDatabase.memory());
    repository = DriftLibraryRepository(database);
  });
  tearDown(() async {
    if (!memoryClosed) await database.close();
  });

  test('joined watch preserves empty tags and punctuation; changes are emitted after one transaction', () async {
    final events = <List<String>>[];
    final subscription = repository.watch().listen(
      (notes) => events.add(
        notes.map((note) => '${note.title}:${note.tags.join('|')}').toList(),
      ),
    );
    addTearDown(subscription.cancel);
    await repository.watch().first;
    final first = await repository.save(
      title: '中文资料',
      body: '正文',
      tags: [' study ', 'study', 'tag,with,comma', "quote'tag"],
    );
    await repository.watch().firstWhere((notes) => notes.isNotEmpty);
    expect((await repository.watch().first).single.tags, [
      "quote'tag",
      'study',
      'tag,with,comma',
    ]);
    final second = await repository.save(title: 'No tag', body: '', tags: []);
    expect((await repository.watch().first).map((note) => note.id), [
      second,
      first,
    ]);
    expect((await repository.watch(query: "' OR 1=1 --").first), isEmpty);
    await repository.save(
      id: first,
      title: 'Edited',
      body: '中文搜索',
      tags: ['new'],
    );
    expect((await repository.watch(query: '中文搜索').first).single.tags, ['new']);
    // No emitted row exposes a new title with only partially replaced tags.
    expect(
      events
          .expand((event) => event)
          .where((line) => line.startsWith('Edited:')),
      everyElement('Edited:new'),
    );
  });

  test(
    'failed relation write rolls back both document changes and old tags',
    () async {
      final id = await repository.save(
        title: 'Original',
        body: 'Keep body',
        tags: ['old'],
      );
      await database.customStatement(
        "CREATE TRIGGER reject_bad BEFORE INSERT ON library_document_tags WHEN NEW.tag_id IN (SELECT id FROM library_tags WHERE name='reject') BEGIN SELECT RAISE(ABORT, 'injected constraint'); END",
      );
      await expectLater(
        repository.save(
          id: id,
          title: 'Should rollback',
          body: 'New body',
          tags: ['good', 'reject'],
        ),
        throwsA(anything),
      );
      final note = (await repository.watch().first).single;
      expect(note.title, 'Original');
      expect(note.body, 'Keep body');
      expect(note.tags, ['old']);
      expect(
        await database
            .select(database.libraryTags)
            .get()
            .then((rows) => rows.map((row) => row.name).toList()),
        ['old'],
      );
    },
  );

  test(
    'archive moves a row between live queries and can be restored',
    () async {
      final id = await repository.save(
        title: 'Archive me',
        body: '',
        tags: ['kept'],
      );
      await repository.setArchived(id, true);
      expect(await repository.watch().first, isEmpty);
      expect((await repository.watch(archived: true).first).single.tags, [
        'kept',
      ]);
      await repository.setArchived(id, false);
      expect((await repository.watch().first).single.id, id);
      await expectLater(repository.setArchived(-1, true), throwsStateError);
      expect(
        () => repository.save(title: ' ', body: '', tags: []),
        throwsArgumentError,
      );
    },
  );

  test(
    'background native connection persists and migrates nonempty v1 only once',
    () async {
      await database.close();
      memoryClosed = true;
      final directory = await Directory.systemTemp.createTemp('database_lab_');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('test/fixtures/library_v1.sqlite')
          .copy('${directory.path}/library.sqlite');
      final first = LibraryDatabase(openNativeDatabase(file).executor);
      final firstRepo = DriftLibraryRepository(first);
      expect((await firstRepo.watch().first).map((note) => note.id), [11, 7]);
      expect((await firstRepo.watch().first).last.body, '旧正文必须保留');
      expect((await firstRepo.watch().first).first.tags, [
        "quote'tag",
        'tag,with,comma',
      ]);
      await firstRepo.setArchived(7, true);
      await first.close();
      final second = LibraryDatabase(
        openNativeDatabase(file).executor,
        beforeMigrationCommit: () => throw StateError('must not migrate twice'),
      );
      try {
        expect(
          (await DriftLibraryRepository(
            second,
          ).watch(archived: true).first).single.id,
          7,
        );
        expect(
          (await second.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          2,
        );
        expect(
          await second.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await second.close();
      }
    },
  );

  test(
    'migration failure leaves schema and nonempty v1 data available for retry',
    () async {
      await database.close();
      memoryClosed = true;
      final directory = await Directory.systemTemp.createTemp(
        'database_lab_rollback_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('test/fixtures/library_v1.sqlite')
          .copy('${directory.path}/library.sqlite');
      final broken = LibraryDatabase(
        openNativeDatabase(file).executor,
        beforeMigrationCommit: () => throw StateError('injected upgrade error'),
      );
      await expectLater(
        DriftLibraryRepository(broken).watch().first,
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('injected upgrade error'),
          ),
        ),
      );
      await broken.close();
      final raw = sqlite.sqlite3.open(file.path);
      try {
        expect(raw.select('PRAGMA user_version').single['user_version'], 1);
        expect(
          raw
              .select('PRAGMA table_info(library_documents)')
              .map((row) => row['name']),
          isNot(contains('archived')),
        );
        expect(
          raw
              .select('SELECT body FROM library_documents WHERE id=7')
              .single['body'],
          '旧正文必须保留',
        );
      } finally {
        raw.close();
      }
      final retry = LibraryDatabase(openNativeDatabase(file).executor);
      try {
        expect(
          (await DriftLibraryRepository(retry).watch().first),
          hasLength(2),
        );
      } finally {
        await retry.close();
      }
    },
  );
}
