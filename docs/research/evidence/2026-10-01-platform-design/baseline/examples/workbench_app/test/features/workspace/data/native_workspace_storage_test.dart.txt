import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_native.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage.dart'
    as facade;
import 'package:workbench_app/features/workspace/data/workspace_storage_stub.dart'
    as unsupported;
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

void main() {
  late Directory directory;
  late NativeWorkspaceStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'workbench_storage_test_',
    );
    storage = NativeWorkspaceStorage(directory.path);
    await storage.initialize();
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  test('conditional factory opens injected native directory and unsupported target is explicit', () async {
    final owner = await facade.openWorkspaceStorage(
      nativeDirectory: directory.path,
    );
    expect(await owner.repository.load(), const WorkspaceSnapshot());
    await owner.repository.save(const WorkspaceSnapshot(revision: 3));
    expect((await owner.repository.load()).revision, 3);
    await owner.close();
    await expectLater(unsupported.openStorage(), throwsUnsupportedError);
  });

  test(
    'serial snapshot writes survive close and reopen and preserve backup',
    () async {
      expect(await storage.load(), const WorkspaceSnapshot());
      const old = WorkspaceSnapshot(
        revision: 1,
        documents: [WorkspaceDocument(id: 'd', title: '中文资料', text: '上次内容')],
      );
      const newest = WorkspaceSnapshot(
        revision: 2,
        todos: [WorkspaceTodo(id: 't', title: '待办')],
      );
      await Future.wait([storage.save(old), storage.save(newest)]);
      expect(await storage.load(), newest);
      final backup = jsonDecode(
        await File('${directory.path}/workspace.json.backup').readAsString(),
      ) as Map<String, dynamic>;
      expect(WorkspaceSnapshot.fromJson(backup), old);
      await storage.close();
      storage = await openStorage(
        nativeDirectory: directory.path,
      ) as NativeWorkspaceStorage;
      expect(await storage.load(), newest);
    },
  );
  test('missing and corrupt current recover valid backup and retain warning/evidence', () async {
    await storage.save(const WorkspaceSnapshot(revision: 1));
    await storage.save(const WorkspaceSnapshot(revision: 2));
    await File('${directory.path}/workspace.json').delete();
    expect((await storage.load()).revision, 1);
    expect(storage.warning, contains('恢复备份'));
    await File('${directory.path}/workspace.json').writeAsString('{broken');
    expect((await storage.load()).revision, 1);
    expect(storage.warning, contains('快照损坏'));
    final preserved = (await directory.list().toList())
        .where((entry) => entry.path.contains('.corrupt_'))
        .single;
    expect(await File(preserved.path).readAsString(), '{broken');
    expect(
      await File('${directory.path}/workspace.json.backup').exists(),
      isTrue,
    );
  });
  test('unsupported snapshot format does not overwrite user content', () async {
    await File('${directory.path}/workspace.json')
        .writeAsString('{"schemaVersion":99}');
    await expectLater(
      storage.load(),
      throwsA(isA<WorkspaceStorageException>()),
    );
    await expectLater(
      storage.save(const WorkspaceSnapshot()),
      throwsA(isA<WorkspaceStorageException>()),
    );
    expect(
      await File('${directory.path}/workspace.json').readAsString(),
      '{"schemaVersion":99}',
    );
  });
  test(
    'staged streamed bytes commit, preview resolves real file, remove works',
    () async {
      final progress = <int>[];
      final key = await storage.stage(
        Stream.fromIterable([
          [1, 2],
          [3, 4, 5],
        ]),
        name: '../image.png',
        onBytes: progress.add,
      );
      expect(progress, [2, 5]);
      await expectLater(
        storage.readBytes(key),
        throwsA(isA<FileSystemException>()),
      );
      expect(await storage.commit(key), key);
      expect(await storage.readBytes(key), [1, 2, 3, 4, 5]);
      expect(await storage.read(key).expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
        4,
        5,
      ]);
      final lease = await storage.openPreview(key);
      expect(await File.fromUri(Uri.parse(lease.uri)).readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
      ]);
      await lease.dispose();
      await storage.remove(key);
      await expectLater(
        storage.openPreview(key),
        throwsA(isA<WorkspaceStorageException>()),
      );
    },
  );
  test('failed streams and abort leave no partial files', () async {
    Stream<List<int>> broken() async* {
      yield [1];
      throw StateError('source lost');
    }

    await expectLater(
      storage.stage(broken(), name: 'bad.mp4'),
      throwsStateError,
    );
    expect(
      await Directory('${directory.path}/staging').list().toList(),
      isEmpty,
    );
    final key = await storage.stage(Stream.value([7]), name: 'file');
    await storage.abort(key);
    await storage.abort(key);
    final discarded = await storage.stage(
      Stream.value([8]),
      name: 'discard.png',
    );
    await storage.cleanupStaging();
    await expectLater(
      storage.commit(discarded),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => storage.read('../workspace.json'),
      throwsA(isA<WorkspaceStorageException>()),
    );
    await expectLater(
      storage.abort('../workspace.json'),
      throwsA(isA<WorkspaceStorageException>()),
    );
    await storage.close();
    await expectLater(
      storage.load(),
      throwsA(isA<WorkspaceStorageException>()),
    );
  });
}
