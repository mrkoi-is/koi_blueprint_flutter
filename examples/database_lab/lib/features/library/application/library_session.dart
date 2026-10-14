import 'dart:async';

import 'package:database_lab/core/database/database_handle.dart';
import 'package:database_lab/features/library/data/drift_library_repository.dart';
import 'package:database_lab/features/library/data/library_database.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';

/// Bootstrap owns this session. Providers only borrow its repository.
final class LibrarySession {
  LibrarySession(DatabaseHandle handle)
    : availability = handle.availability,
      _database = LibraryDatabase(handle.executor) {
    repository = DriftLibraryRepository(_database);
  }
  final LibraryDatabase _database;
  final DatabaseAvailability availability;
  late final LibraryRepository repository;
  Future<void>? _closing;

  Future<void> initialize() async {
    // Forces open/migration before a usable UI is exposed.
    await _database
        .customSelect('SELECT count(*) AS count FROM library_documents')
        .get();
  }

  Future<void> close() => _closing ??= _database.close();
}
