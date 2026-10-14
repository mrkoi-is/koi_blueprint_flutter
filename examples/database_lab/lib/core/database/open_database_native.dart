import 'dart:io';

import 'package:database_lab/core/database/database_handle.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<DatabaseHandle> openDatabase({String name = 'koi_library'}) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return openNativeDatabase(File(p.join(directory.path, '$name.sqlite')));
}

DatabaseHandle openNativeDatabase(File file) => DatabaseHandle(
  NativeDatabase.createInBackground(file),
  const DatabaseAvailability(
    mode: 'SQLite · 后台隔离线程',
    persistent: true,
    multiTabSafe: true,
  ),
);
