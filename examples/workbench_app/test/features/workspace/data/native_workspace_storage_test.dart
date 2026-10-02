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

  test('second owner cannot load, clean active staging or overwrite; retry after close succeeds', () async {
    final key = await storage.stage(
      Stream.value([1, 2, 3]),
      name: 'active.png',
    );
    await storage.save(
      const WorkspaceSnapshot(
        documents: [WorkspaceDocument(id: 'a', title: '中文资料')],
      ),
    );
    final second = NativeWorkspaceStorage(directory.path);
    await expectLater(second.initialize(), throwsA(isA<WorkspaceInUse>()));
    await expectLater(
      second.cleanupStaging(),
      throwsA(isA<WorkspaceStorageException>()),
    );
    expect(await storage.commit(key), key);
    await storage.close();
    await second.initialize();
    expect((await second.load()).documents.single.title, '中文资料');
    expect(await second.readBytes(key), [1, 2, 3]);
    await second.close();
  });

  test(
    'closed owner cannot reacquire a lock; a fresh owner remains usable',
    () async {
      await storage.close();
      await expectLater(
        storage.initialize(),
        throwsA(isA<WorkspaceStorageException>()),
      );
      final fresh = NativeWorkspaceStorage(directory.path);
      await fresh.initialize();
      await fresh.save(const WorkspaceSnapshot(revision: 1));
      await fresh.close();
    },
  );

  test(
    'legacy snapshot starts at storage version zero; conflicts preserve bytes',
    () async {
      final file = File('${directory.path}/workspace.json');
      await file.writeAsString(
        jsonEncode(const WorkspaceSnapshot(revision: 900).toJson()),
      );
      expect((await storage.load()).revision, 900);
      expect(storage.persistedVersion, 0);
      await storage.save(
        const WorkspaceSnapshot(revision: 901),
        expectedVersion: 0,
      );
      expect(storage.persistedVersion, 1);
      final original = await file.readAsBytes();
      await expectLater(
        storage.save(
          const WorkspaceSnapshot(revision: 999),
          expectedVersion: 0,
        ),
        throwsA(isA<WorkspaceConflict>()),
      );
      expect(await file.readAsBytes(), original);
    },
  );

  test(
    'close waits for active streamed staging before releasing ownership',
    () async {
      final bytes = StreamController<List<int>>();
      final entered = Completer<void>();
      final staging = storage.stage(
        bytes.stream,
        name: 'stream.png',
        onBytes: (_) {
          if (!entered.isCompleted) entered.complete();
        },
      );
      bytes.add([1, 2]);
      await entered.future;
      var closed = false;
      final closing = storage.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      final second = NativeWorkspaceStorage(directory.path);
      await expectLater(second.initialize(), throwsA(isA<WorkspaceInUse>()));
      await bytes.close();
      final key = await staging;
      await closing;
      await second.initialize();
      await second.cleanupStaging();
      await expectLater(
        second.commit(key),
        throwsA(isA<FileSystemException>()),
      );
      await second.close();
    },
  );

  test(
    'native ownership excludes another Dart process and releases on close',
    () async {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      expect(
        flutterRoot,
        isNotNull,
        reason: 'Flutter test must expose its selected SDK',
      );
      final dart = '$flutterRoot/bin/dart${Platform.isWindows ? '.exe' : ''}';
      Future<String> probe() async {
        final result = await Process.run(dart, [
          'test/support/process_lock_probe.dart',
          directory.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return '${result.stdout}'.trim();
      }

      expect(await probe(), 'busy');
      await storage.close();
      expect(await probe(), 'acquired');
    },
  );

  test('conditional factory opens injected native directory and unsupported target is explicit', () async {
    await storage.close();
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
