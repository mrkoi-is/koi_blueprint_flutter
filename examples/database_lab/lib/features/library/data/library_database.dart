import 'dart:async';

import 'package:drift/drift.dart';

part 'library_database.g.dart';

class LibraryDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get body => text()();
  // v2 adds a user-visible archive action without inventing historical dates.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class LibraryTags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class LibraryDocumentTags extends Table {
  IntColumn get documentId => integer().references(
    LibraryDocuments,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get tagId =>
      integer().references(LibraryTags, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column<Object>> get primaryKey => {documentId, tagId};
}

@DriftDatabase(tables: [LibraryDocuments, LibraryTags, LibraryDocumentTags])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(super.executor, {this.beforeMigrationCommit});

  /// Failure injection for verifying transactional migration rollback.
  final FutureOr<void> Function()? beforeMigrationCommit;

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from != 1 || to != 2) {
        throw StateError('Unsupported database migration: $from → $to');
      }
      await transaction(() async {
        await migrator.addColumn(libraryDocuments, libraryDocuments.archived);
        await beforeMigrationCommit?.call();
        final violations = await customSelect('PRAGMA foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw StateError('Database relationships are invalid');
        }
      });
    },
    beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
  );
}
