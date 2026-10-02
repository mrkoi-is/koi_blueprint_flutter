import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_native.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'fixtures/workspace_v1_fixture.dart';

void main() {
  late Directory root;
  late File current;
  late NativeWorkspaceStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('koi_migration_');
    current = File('${root.path}/workspace.json');
    await current.writeAsString(workspaceV1Fixture);
    storage = NativeWorkspaceStorage(root.path);
    await storage.initialize();
    await File('${root.path}/assets/kept.png').writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    await storage.close();
    await root.delete(recursive: true);
  });

  test(
    'owner commits v2 exactly once with CAS, raw v1 backup and untouched asset',
    () async {
      final blocked = NativeWorkspaceStorage(root.path);
      await expectLater(blocked.initialize(), throwsA(isA<WorkspaceInUse>()));
      expect(await current.readAsString(), workspaceV1Fixture);
      final snapshot = await storage.load();
      expect(snapshot.schemaVersion, 2);
      expect(storage.persistedVersion, 8);
      expect(jsonDecode(await current.readAsString())['schemaVersion'], 2);
      expect(
        await File('${root.path}/workspace.json.backup').readAsString(),
        workspaceV1Fixture,
      );
      expect(await storage.readBytes('kept.png'), [1, 2, 3]);
      expect(await storage.load(), snapshot);
      expect(storage.persistedVersion, 8);
      await expectLater(
        storage.save(snapshot, expectedVersion: 7),
        throwsA(isA<WorkspaceConflict>()),
      );
      expect(storage.persistedVersion, 8);
      await storage.close();
      storage = NativeWorkspaceStorage(root.path);
      await storage.initialize();
      expect(await storage.load(), snapshot);
      expect(storage.persistedVersion, 8);
    },
  );

  test('failed migration preserves original snapshot and existing backup; retry works', () async {
    await storage.close();
    var fail = true;
    storage = NativeWorkspaceStorage(
      root.path,
      beforeSnapshotCommit: () {
        if (fail) throw const FileSystemException('injected disk failure');
      },
    );
    await storage.initialize();
    final backup = File('${root.path}/workspace.json.backup');
    await backup.writeAsString('existing backup bytes');
    await expectLater(storage.load(), throwsA(isA<FileSystemException>()));
    expect(await current.readAsString(), workspaceV1Fixture);
    expect(await backup.readAsString(), 'existing backup bytes');
    expect(storage.persistedVersion, 7);
    fail = false;
    expect((await storage.load()).schemaVersion, 2);
    expect(storage.persistedVersion, 8);
  });

  test(
    'migration checks the same source again immediately before replacement',
    () async {
      await storage.close();
      final newer = workspaceV1Fixture.replaceFirst(
        '"storageVersion": 7',
        '"storageVersion": 9',
      );
      storage = NativeWorkspaceStorage(
        root.path,
        beforeSnapshotCommit: () async {
          await current.writeAsString(newer);
        },
      );
      await storage.initialize();
      await expectLater(storage.load(), throwsA(isA<WorkspaceConflict>()));
      expect(await current.readAsString(), newer);
      expect(await storage.readBytes('kept.png'), [1, 2, 3]);
    },
  );
}
