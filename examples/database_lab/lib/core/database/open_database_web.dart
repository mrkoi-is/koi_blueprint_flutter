import 'dart:typed_data';

import 'package:database_lab/core/database/database_handle.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:drift/wasm.dart';

Future<DatabaseHandle> openDatabase({String name = 'koi_library'}) =>
    openWebDatabase(name: name);

Future<DatabaseHandle> openWebDatabase({
  required String name,
  Uri? sqlite3Uri,
  Uri? workerUri,
  Future<Uint8List?> Function()? initializeDatabase,
}) async {
  final result = await WasmDatabase.open(
    databaseName: name,
    sqlite3Uri: sqlite3Uri ?? Uri.base.resolve('sqlite3.wasm'),
    driftWorkerUri: workerUri ?? Uri.base.resolve('drift_worker.dart.js'),
    initializeDatabase: initializeDatabase,
  );
  final mode = result.chosenImplementation.name;
  return DatabaseHandle(
    result.resolvedExecutor,
    DatabaseAvailability(
      mode: mode,
      persistent: mode != 'inMemory',
      multiTabSafe: mode != 'unsafeIndexedDb' && mode != 'inMemory',
    ),
  );
}
