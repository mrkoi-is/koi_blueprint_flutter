import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/application/snapshot_job_history_repository.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_native.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

void main() {
  late Directory directory;
  late NativeWorkspaceStorage storage;
  late _Picker picker;
  late WorkspaceSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'workbench_session_test_',
    );
    storage = NativeWorkspaceStorage(directory.path);
    await storage.initialize();
    picker = _Picker();
    session = WorkspaceSession(
      repository: storage,
      assetStore: storage,
      fileImportPort: picker,
      imageThumbnail: (bytes) async => _png,
      debounce: const Duration(milliseconds: 20),
    );
    await session.initialize();
  });
  tearDown(() async {
    await session.dispose();
    await storage.close();
    await directory.delete(recursive: true);
  });

  test(
    'editing, renamed Chinese content, selection and todos survive reopening',
    () async {
      final id = session.createDocument(title: '中文资料');
      session.editDocument(id, '持续草稿');
      session.renameDocument(id, '改名');
      final todo = session.addTodo('实现持久化');
      session.updateTodo(todo, title: '实现并验证', completed: true);
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(
          themeMode: WorkspaceThemeMode.dark,
          density: WorkspaceDensity.compact,
          sidebarWidth: 312,
        ),
      );
      expect(session.state.snapshot.documents.single.dirty, isTrue);
      await session.changes
          .firstWhere(
            (state) =>
                !state.saving &&
                (state.error != null || !state.snapshot.documents.single.dirty),
          )
          .timeout(const Duration(seconds: 10));
      expect(session.state.error, isNull);
      expect(session.state.snapshot.documents.single.dirty, isFalse);
      await session.dispose();
      session = WorkspaceSession(
        repository: storage,
        assetStore: storage,
        fileImportPort: picker,
      );
      await session.initialize();
      expect(session.state.snapshot.documents.single.text, '持续草稿');
      expect(session.state.snapshot.documents.single.title, '改名');
      expect(session.state.snapshot.preferences.selectedDocumentId, id);
      expect(session.state.snapshot.preferences.sidebarWidth, 312);
      expect(session.state.snapshot.todos.single.completed, isTrue);
      session.deleteTodo(todo);
      session.deleteDocument(id);
      expect(session.state.snapshot.todos, isEmpty);
      expect(session.state.snapshot.preferences.selectedDocumentId, isNull);
    },
  );

  test(
    'text imports real bytes, records actual progress, closes selected source',
    () async {
      final source = _Source('资料.md', utf8.encode('真实中文内容'));
      picker.results.add(FilesSelected([source]));
      await session.importFiles(ImportKind.text);
      expect(session.state.snapshot.documents.single.text, '真实中文内容');
      expect(session.state.snapshot.jobs.single.status, JobStatus.succeeded);
      expect(
        session.state.snapshot.jobs.single.processedBytes,
        source.byteLength,
      );
      expect(source.closed, isTrue);
      expect((await storage.load()).documents.single.text, '真实中文内容');
    },
  );

  test('text read has real byte progress while blocked snapshot commit is indeterminate', () async {
    await session.dispose();
    final repository = _ControlledRepository();
    session = WorkspaceSession(
      repository: repository,
      assetStore: storage,
      fileImportPort: picker,
      debounce: const Duration(days: 1),
    );
    await session.initialize();
    final seen = <WorkspaceJob>[];
    final subscription = session.changes.listen((state) {
      if (state.snapshot.jobs.isNotEmpty) seen.add(state.snapshot.jobs.last);
    });
    final source = _Source('资料.txt', utf8.encode('真实读取'));
    picker.results.add(FilesSelected([source]));
    final saving = session.changes.firstWhere((state) => state.saving);
    final importing = session.importFiles(ImportKind.text);
    await saving;
    expect(
      seen.any(
        (job) => !job.indeterminate && job.processedBytes == source.byteLength,
      ),
      isTrue,
    );
    expect(session.state.snapshot.jobs.single.status, JobStatus.running);
    expect(session.state.snapshot.jobs.single.indeterminate, isTrue);
    expect(
      session.state.snapshot.jobs.single.processedBytes,
      source.byteLength,
    );
    expect(session.state.snapshot.jobs.single.totalBytes, source.byteLength);
    repository.block = false;
    repository.gate!.complete();
    await importing;
    expect(session.state.snapshot.jobs.single.status, JobStatus.succeeded);
    await subscription.cancel();
  });

  for (final count in [1, 2]) {
    test(
      '$count media file(s) keep real byte totals while every asset commit waits indeterminate',
      () async {
        await session.dispose();
        final stagedStore = _BlockingAssetStore(storage);
        session = WorkspaceSession(
          repository: storage,
          assetStore: stagedStore,
          fileImportPort: picker,
          debounce: const Duration(days: 1),
        );
        await session.initialize();
        final sources = List.generate(
          count,
          (index) => _Source('video_$index.mp4', [
            0,
            0,
            0,
            16,
            102,
            116,
            121,
            112,
            105,
            115,
            111,
            109,
          ]),
        );
        picker.results.add(FilesSelected(sources));
        final seen = <WorkspaceJob>[];
        final subscription = session.changes.listen((state) {
          if (state.snapshot.jobs.isNotEmpty) {
            seen.add(state.snapshot.jobs.last);
          }
        });
        var waiting = stagedStore.entered.stream.first;
        final importing = session.importFiles(ImportKind.media);
        for (var index = 0; index < count; index++) {
          await waiting;
          final job = session.state.snapshot.jobs.single;
          expect(job.status, JobStatus.running);
          expect(job.indeterminate, isTrue);
          expect(job.processedBytes, (index + 1) * 12);
          expect(job.totalBytes, count * 12);
          expect(
            seen.any(
              (job) =>
                  !job.indeterminate && job.processedBytes == (index + 1) * 12,
            ),
            isTrue,
          );
          if (index + 1 < count) waiting = stagedStore.entered.stream.first;
          stagedStore.gates[index].complete();
        }
        await importing;
        expect(session.state.snapshot.jobs.single.status, JobStatus.succeeded);
        for (final asset in session.state.snapshot.assets) {
          expect(
            await storage.readBytes(asset.storageKey),
            sources.first.bytes,
          );
        }
        await subscription.cancel();
        await stagedStore.entered.close();
      },
    );
  }

  test('media stores source and real supplied thumbnail as separate durable assets', () async {
    final source = _Source('素材.png', _png);
    picker.results.add(FilesSelected([source]));
    await session.importFiles(ImportKind.media);
    final asset = session.state.snapshot.assets.single;
    expect(asset.thumbnailStatus, ThumbnailStatus.ready);
    expect(asset.storageKey, isNot(asset.thumbnailKey));
    expect(await storage.readBytes(asset.storageKey), _png);
    expect(await storage.readBytes(asset.thumbnailKey!), _png);
    expect(
      session.state.snapshot.jobs.map((job) => job.status),
      everyElement(JobStatus.succeeded),
    );
    expect(source.closed, isTrue);
  });

  test(
    'limits and mismatched format/length fail without persisting partial media',
    () async {
      final tooBig = _Source('big.txt', [1], declaredLength: 300 * 1024);
      picker.results.add(FilesSelected([tooBig]));
      await session.importFiles(ImportKind.text);
      expect(session.state.snapshot.jobs.last.status, JobStatus.failed);
      expect(tooBig.opened, isFalse);
      final unsupported = _Source('bad.pdf', [1]);
      picker.results.add(FilesSelected([unsupported]));
      await session.importFiles(ImportKind.text);
      expect(session.state.snapshot.jobs.last.error, contains('不支持'));
      final fakeImage = _Source('fake.png', [1, 2, 3]);
      picker.results.add(FilesSelected([fakeImage]));
      await session.importFiles(ImportKind.media);
      expect(session.state.snapshot.jobs.last.error, contains('类型不符'));
      final wrongLength = _Source('wrong.txt', [1, 2], declaredLength: 1);
      picker.results.add(FilesSelected([wrongLength]));
      await session.importFiles(ImportKind.text);
      expect(session.state.snapshot.jobs.last.error, contains('长度不一致'));
      expect(session.state.snapshot.assets, isEmpty);
      expect(
        await Directory('${directory.path}/assets').list().toList(),
        isEmpty,
      );
      expect(
        await Directory('${directory.path}/staging').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'cancel actually cancels an outstanding source stream and removes staging',
    () async {
      var subscriptionCancelled = false;
      final sourceStream = StreamController<List<int>>(
        onCancel: () {
          subscriptionCancelled = true;
        },
      );
      final source = _Source(
        'slow.mp4',
        [1],
        declaredLength: 1024,
        customStream: sourceStream.stream,
      );
      picker.results.add(FilesSelected([source]));
      final running = session.importFiles(ImportKind.media);
      await Future<void>.delayed(Duration.zero);
      sourceStream.add([0, 0, 0, 16, 102, 116, 121, 112, 105, 115, 111, 109]);
      await session.changes.firstWhere(
        (state) => state.snapshot.jobs.single.processedBytes > 0,
      );
      session.cancelJob(session.state.snapshot.jobs.single.id);
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelling);
      await running;
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelled);
      expect(subscriptionCancelled, isTrue);
      expect(source.closed, isTrue);
      expect(
        await Directory('${directory.path}/staging').list().toList(),
        isEmpty,
      );
      await sourceStream.close();
    },
  );

  test('retry keeps task identity and archives the previous attempt', () async {
    picker.results.add(const ImportFailed('设备拒绝读取'));
    await session.importFiles(ImportKind.text);
    final failed = session.state.snapshot.jobs.single;
    picker.results.add(
      FilesSelected([_Source('retry.txt', utf8.encode('重试正文'))]),
    );
    await session.retryJob(failed.id);
    expect(picker.requests, 2);
    expect(session.state.snapshot.jobs, hasLength(1));
    expect(session.state.snapshot.jobs.last.id, failed.id);
    expect(session.state.snapshot.jobs.last.currentAttempt, 2);
    expect(session.state.snapshot.jobHistory.first, failed);
    expect(session.state.snapshot.jobs.last.status, JobStatus.succeeded);
  });

  test('UTC attempt timestamps and bounded history survive restart; clear only removes history', () async {
    await session.dispose();
    var now = DateTime.utc(2026, 10, 2, 10);
    session = WorkspaceSession(
      repository: storage,
      assetStore: storage,
      fileImportPort: picker,
      clock: () => now,
      historyLimit: 2,
    );
    await session.initialize();
    final document = session.createDocument(title: '保留资料');
    picker.results.add(const ImportFailed('first'));
    await session.importFiles(ImportKind.text);
    final id = session.state.snapshot.jobs.single.id;
    expect(session.state.snapshot.jobs.single.startedAt, now);
    expect(session.state.snapshot.jobs.single.finishedAt, now);
    for (var attempt = 2; attempt <= 3; attempt++) {
      now = now.add(const Duration(minutes: 1));
      picker.results.add(ImportFailed('attempt $attempt'));
      await session.retryJob(id);
    }
    final history = SnapshotJobHistoryRepository(session);
    expect((await history.read(jobId: id)).map((job) => job.currentAttempt), [
      3,
      2,
    ]);
    expect(session.state.snapshot.jobs.single.startedAt!.isUtc, isTrue);
    await session.dispose();
    session = WorkspaceSession(
      repository: storage,
      assetStore: storage,
      fileImportPort: picker,
    );
    await session.initialize();
    expect(session.state.snapshot.jobs.single.currentAttempt, 3);
    expect(session.state.snapshot.jobHistory, hasLength(2));
    await SnapshotJobHistoryRepository(session).clear();
    expect(session.state.snapshot.jobHistory, isEmpty);
    expect(session.state.snapshot.jobs.single.id, id);
    expect(session.state.snapshot.documents.single.id, document);
    expect((await storage.load()).jobHistory, isEmpty);
  });

  test('10000 byte events retain exact totals with bounded observer and durable updates', () async {
    await session.dispose();
    final repository = _ControlledRepository()..block = false;
    session = WorkspaceSession(
      repository: repository,
      assetStore: storage,
      fileImportPort: picker,
      debounce: const Duration(days: 1),
      progressInterval: const Duration(days: 1),
      checkpointInterval: const Duration(days: 1),
      clock: () => DateTime.utc(2026, 10, 2),
    );
    await session.initialize();
    var events = 0;
    final sub = session.changes.listen((_) => events++);
    picker.results.add(
      FilesSelected([
        _Source(
          'large.txt',
          [],
          declaredLength: 10000,
          customStream: Stream.fromIterable(List.generate(10000, (_) => [65])),
        ),
      ]),
    );
    await session.importFiles(ImportKind.text);
    expect(session.state.snapshot.jobs.single.processedBytes, 10000);
    expect(session.state.snapshot.jobs.single.status, JobStatus.succeeded);
    expect(session.state.snapshot.documents.single.text.length, 10000);
    expect(session.state.snapshot.revision, lessThan(20));
    expect(events, lessThan(25));
    expect(repository.saved.length, lessThan(10));
    expect(repository.saved.last.jobs.single.processedBytes, 10000);
    await sub.cancel();
  });

  test('cleanup failure does not leak later selected sources or throw an unhandled command', () async {
    final first = _Source('first.txt', [1], failClose: true);
    final second = _Source('second.txt', [2]);
    picker.results.add(FilesSelected([first, second]));
    await session.importFiles(ImportKind.text);
    expect(first.closed, isTrue);
    expect(second.closed, isTrue);
    expect(session.state.snapshot.jobs.single.status, JobStatus.failed);
    expect(session.state.snapshot.jobs.single.error, contains('释放导入源失败'));
  });

  test(
    'selected source is still closed when picker completes after cancellation',
    () async {
      final selection = Completer<FileImportResult>();
      picker.pending = selection.future;
      final running = session.importFiles(ImportKind.text);
      await Future<void>.delayed(Duration.zero);
      session.cancelJob(session.state.snapshot.jobs.single.id);
      final source = _Source('late.txt', [1]);
      selection.complete(FilesSelected([source]));
      await running;
      expect(source.closed, isTrue);
      expect(source.opened, isFalse);
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelled);
    },
  );

  test('failed initialization exposes storage error and retry restores original durable content', () async {
    await session.dispose();
    await storage.close();
    final retryDirectory = '${directory.path}/load_retry';
    storage = NativeWorkspaceStorage(retryDirectory);
    await storage.initialize();
    final assetKey = await storage.commit(
      await storage.stage(Stream.value(_png), name: '原图片.png'),
    );
    final original = WorkspaceSnapshot(
      revision: 9,
      documents: const [
        WorkspaceDocument(
          id: 'document',
          title: '原中文资料',
          text: '已保存内容，不应因启动失败丢失',
          revision: 7,
          savedRevision: 7,
        ),
      ],
      assets: [
        WorkspaceAsset(
          id: 'asset',
          name: '原图片.png',
          kind: MediaKind.image,
          byteLength: _png.length,
          storageKey: assetKey,
        ),
      ],
      todos: const [
        WorkspaceTodo(id: 'todo', title: '恢复已完成待办', completed: true),
      ],
      preferences: const WorkspacePreferences(
        themeMode: WorkspaceThemeMode.dark,
        density: WorkspaceDensity.compact,
        navId: 'media',
        selectedDocumentId: 'document',
        selectedAssetId: 'asset',
      ),
    );
    await storage.save(original);
    final snapshotFile = File('$retryDirectory/workspace.json');
    final originalBytes = await snapshotFile.readAsBytes();
    const damagedContents = '{快照损坏，需要修复';
    await snapshotFile.writeAsString(damagedContents, flush: true);
    session = WorkspaceSession(
      repository: storage,
      assetStore: storage,
      fileImportPort: picker,
    );
    await expectLater(
      session.initialize(),
      throwsA(isA<WorkspaceStorageException>()),
    );
    expect(session.state.initialized, isFalse);
    expect(session.state.error, contains('工作区快照损坏'));

    await session.save();
    expect(await snapshotFile.readAsString(), damagedContents);
    expect(
      await File('$retryDirectory/workspace.json.backup').exists(),
      isFalse,
    );
    expect(
      await File('$retryDirectory/workspace.json.pending').exists(),
      isFalse,
    );
    expect(await storage.readBytes(assetKey), _png);

    await snapshotFile.writeAsBytes(originalBytes, flush: true);
    await session.initialize();
    expect(session.state.initialized, isTrue);
    expect(session.state.error, isNull);
    expect(session.state.snapshot, original);
    expect(session.state.snapshot.documents.single.dirty, isFalse);
    expect(await snapshotFile.readAsBytes(), originalBytes);
    expect(await storage.readBytes(assetKey), _png);
  });

  test('startup interrupts old tasks, cleans temporary files, preserves saved data', () async {
    await session.dispose();
    await storage.save(
      const WorkspaceSnapshot(
        jobs: [
          WorkspaceJob(
            id: 'unfinished',
            kind: JobKind.thumbnail,
            name: '旧任务',
            status: JobStatus.running,
          ),
        ],
        assets: [
          WorkspaceAsset(
            id: 'a',
            name: 'a.mp4',
            kind: MediaKind.video,
            byteLength: 1,
            storageKey: 'a',
            thumbnailStatus: ThumbnailStatus.generating,
          ),
        ],
      ),
    );
    await storage.stage(Stream.value([8]), name: 'partial.png');
    session = WorkspaceSession(
      repository: storage,
      assetStore: storage,
      fileImportPort: picker,
    );
    await session.initialize();
    expect(session.state.snapshot.jobs.single.status, JobStatus.interrupted);
    expect(
      session.state.snapshot.assets.single.thumbnailStatus,
      ThumbnailStatus.failed,
    );
    expect(
      await Directory('${directory.path}/staging').list().toList(),
      isEmpty,
    );
  });

  test('thumbnail cancellation settles only after callback cleanup and never commits bytes', () async {
    picker.results.add(
      FilesSelected([
        _Source('movie.mp4', [
          0,
          0,
          0,
          16,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
        ]),
      ]),
    );
    await session.importFiles(ImportKind.media);
    final asset = session.state.snapshot.assets.single;
    final jobId = session.beginThumbnail(asset.id);
    session.cancelJob(jobId);
    expect(session.isJobCancelled(jobId), isTrue);
    expect(session.state.snapshot.jobs.last.status, JobStatus.cancelling);
    await session.storeThumbnail(asset.id, _png, jobId: jobId);
    expect(session.state.snapshot.jobs.last.status, JobStatus.cancelled);
    expect(session.state.snapshot.assets.single.thumbnailKey, isNull);
    expect(
      session.state.snapshot.assets.single.thumbnailStatus,
      ThumbnailStatus.none,
    );
    await expectLater(session.retryJob(jobId), throwsStateError);
  });

  test(
    'save only clears captured document revision and retains error on failure',
    () async {
      await session.dispose();
      final repository = _ControlledRepository();
      session = WorkspaceSession(
        repository: repository,
        assetStore: storage,
        fileImportPort: picker,
        debounce: const Duration(days: 1),
      );
      await session.initialize();
      final id = session.createDocument(text: 'first');
      final saving = session.save();
      await Future<void>.delayed(Duration.zero);
      session.editDocument(id, 'second');
      repository.gate!.complete();
      await saving;
      expect(session.state.snapshot.documents.single.dirty, isTrue);
      expect(repository.saved.single.documents.single.text, 'first');
      repository.fail = true;
      await session.save();
      expect(session.state.error, contains('保存失败'));
      expect(session.state.snapshot.documents.single.text, 'second');
      expect(session.state.snapshot.documents.single.dirty, isTrue);
      repository.fail = false;
      repository.block = false;
      await session.save();
      expect(session.state.snapshot.documents.single.dirty, isFalse);
      expect(session.state.error, isNull);
    },
  );

  test('failed thumbnail save rolls back missing key and keeps previous durable thumbnail', () async {
    picker.results.add(FilesSelected([_Source('image.png', _png)]));
    await session.importFiles(ImportKind.media);
    final original = session.state.snapshot.assets.single;
    await session.dispose();
    final repository = _ControlledRepository(initial: await storage.load())
      ..block = false;
    session = WorkspaceSession(
      repository: repository,
      assetStore: storage,
      fileImportPort: picker,
    );
    await session.initialize();
    repository.fail = true;
    await session.storeThumbnail(original.id, [255, 216, 255, 1]);
    expect(
      session.state.snapshot.assets.single.thumbnailKey,
      original.thumbnailKey,
    );
    expect(await storage.readBytes(original.thumbnailKey!), _png);
    expect(
      session.state.snapshot.assets.single.thumbnailStatus,
      ThumbnailStatus.failed,
    );
    expect(session.state.snapshot.jobs.last.status, JobStatus.failed);
    expect(
      (await Directory('${directory.path}/assets').list().toList()).length,
      2,
    );
    repository.fail = false;
  });

  for (final failRollback in [false, true]) {
    test(
      'thumbnail cancellation during durable save ${failRollback ? 'retains bytes when rollback fails' : 'restores old metadata before cleaning new bytes'}',
      () async {
        picker.results.add(FilesSelected([_Source('image.png', _png)]));
        await session.importFiles(ImportKind.media);
        final original = session.state.snapshot.assets.single;
        await session.dispose();
        final repository = _GatedNativeRepository(storage)
          ..failAfterBlockedSave = failRollback;
        session = WorkspaceSession(
          repository: repository,
          assetStore: storage,
          fileImportPort: picker,
          imageThumbnail: (bytes) async => _png,
          debounce: const Duration(days: 1),
        );
        await session.initialize();
        repository.blockNext = true;
        final statuses = <JobStatus>{};
        final subscription = session.changes.listen((state) {
          final job = state.snapshot.jobs.last;
          if (job.terminal) statuses.add(job.status);
        });
        final newBytes = [255, 216, 255, 9];
        final replacing = session.storeThumbnail(original.id, newBytes);
        await repository.entered.future;
        final jobId = session.state.snapshot.jobs.last.id;
        session.cancelJob(jobId);
        expect(session.state.snapshot.jobs.last.status, JobStatus.cancelling);
        repository.release.complete();
        await replacing;
        final persisted = await storage.load();
        final asset = session.state.snapshot.assets.single;
        expect(await storage.readBytes(original.thumbnailKey!), _png);
        expect(
          await Directory('${directory.path}/staging').list().toList(),
          isEmpty,
        );
        if (failRollback) {
          expect(session.state.snapshot.jobs.last.status, JobStatus.failed);
          expect(session.state.snapshot.jobs.last.error, contains('回滚保存失败'));
          expect(session.state.error, isNotNull);
          expect(asset.thumbnailKey, isNot(original.thumbnailKey));
          expect(persisted.assets.single.thumbnailKey, asset.thumbnailKey);
          expect(await storage.readBytes(asset.thumbnailKey!), newBytes);
          expect(statuses, {JobStatus.failed});
          repository.failWrites = false;
          await session.retryJob(jobId);
          expect(session.state.snapshot.jobs.last.status, JobStatus.succeeded);
          expect(
            session.state.snapshot.jobHistory
                .firstWhere((job) => job.id == jobId && job.currentAttempt == 1)
                .status,
            JobStatus.failed,
          );
        } else {
          expect(session.state.snapshot.jobs.last.status, JobStatus.cancelled);
          expect(statuses, {JobStatus.cancelled});
          expect(asset.thumbnailKey, original.thumbnailKey);
          expect(asset.thumbnailStatus, ThumbnailStatus.ready);
          expect(persisted.assets.single, original);
          expect(persisted.jobs.last.status, JobStatus.cancelled);
          expect(
            (await Directory(
              '${directory.path}/assets',
            ).list().toList()).length,
            2,
          );
        }
        await subscription.cancel();
      },
    );
  }

  for (final kind in ImportKind.values) {
    test(
      '$kind cancellation during snapshot commit rolls back only the current file',
      () async {
        final originalId = session.createDocument(title: '已有资料', text: '保留正文');
        await session.save();
        final original = session.state.snapshot.documents.single;
        await session.dispose();
        final repository = _GatedNativeRepository(storage);
        session = WorkspaceSession(
          repository: repository,
          assetStore: storage,
          fileImportPort: picker,
          debounce: const Duration(days: 1),
        );
        await session.initialize();
        repository.blockNext = true;
        final source = kind == ImportKind.text
            ? _Source('new.txt', utf8.encode('取消中的新资料'))
            : _Source('new.png', _png);
        picker.results.add(FilesSelected([source]));
        final importing = session.importFiles(kind);
        await repository.entered.future;
        session.cancelJob(session.state.snapshot.jobs.last.id);
        expect(session.state.snapshot.jobs.last.status, JobStatus.cancelling);
        repository.release.complete();
        await importing;
        expect(session.state.snapshot.jobs.last.status, JobStatus.cancelled);
        expect(session.state.snapshot.documents, [original]);
        expect(session.state.snapshot.assets, isEmpty);
        expect(
          session.state.snapshot.preferences.selectedDocumentId,
          originalId,
        );
        expect(session.state.snapshot.preferences.selectedAssetId, isNull);
        final persisted = await storage.load();
        expect(persisted.documents, [original]);
        expect(persisted.assets, isEmpty);
        expect(persisted.jobs.last.status, JobStatus.cancelled);
        expect(source.closed, isTrue);
        expect(
          await Directory('${directory.path}/assets').list().toList(),
          isEmpty,
        );
      },
    );
  }

  test('cancellation during old thumbnail cleanup waits for removal and retains the new durable image', () async {
    picker.results.add(FilesSelected([_Source('image.png', _png)]));
    await session.importFiles(ImportKind.media);
    final original = session.state.snapshot.assets.single;
    await session.dispose();
    final cleanup = _ThumbnailCleanupGate(storage, original.thumbnailKey!);
    session = WorkspaceSession(
      repository: storage,
      assetStore: cleanup,
      fileImportPort: picker,
      debounce: const Duration(days: 1),
    );
    await session.initialize();
    final statuses = <JobStatus>{};
    final subscription = session.changes.listen((state) {
      final job = state.snapshot.jobs.last;
      if (job.terminal) statuses.add(job.status);
    });
    final newBytes = [255, 216, 255, 9];
    final replacing = session.storeThumbnail(original.id, newBytes);
    await cleanup.entered.future;
    final newKey = session.state.snapshot.assets.single.thumbnailKey!;
    expect(newKey, isNot(original.thumbnailKey));
    expect((await storage.load()).assets.single.thumbnailKey, newKey);
    session.cancelJob(session.state.snapshot.jobs.last.id);
    expect(session.state.snapshot.jobs.last.status, JobStatus.cancelling);
    expect(statuses, isEmpty);
    expect(await storage.readBytes(original.thumbnailKey!), _png);
    cleanup.release.complete();
    await replacing;
    expect(session.state.snapshot.jobs.last.status, JobStatus.cancelled);
    expect(statuses, {JobStatus.cancelled});
    final asset = session.state.snapshot.assets.single;
    expect(asset.thumbnailKey, newKey);
    expect(asset.thumbnailStatus, ThumbnailStatus.ready);
    expect(await storage.readBytes(newKey), newBytes);
    await expectLater(
      storage.readBytes(original.thumbnailKey!),
      throwsA(isA<FileSystemException>()),
    );
    final persisted = await storage.load();
    expect(persisted.assets.single, asset);
    expect(persisted.jobs.last.status, JobStatus.cancelled);
    await subscription.cancel();
  });

  test('media import cancellation retains durable bytes and fails visibly when compensation fails', () async {
    await session.dispose();
    final repository = _GatedNativeRepository(storage)
      ..failAfterBlockedSave = true;
    session = WorkspaceSession(
      repository: repository,
      assetStore: storage,
      fileImportPort: picker,
      debounce: const Duration(days: 1),
    );
    await session.initialize();
    repository.blockNext = true;
    picker.results.add(FilesSelected([_Source('new.png', _png)]));
    final importing = session.importFiles(ImportKind.media);
    await repository.entered.future;
    session.cancelJob(session.state.snapshot.jobs.last.id);
    repository.release.complete();
    await importing;
    expect(session.state.snapshot.jobs.last.status, JobStatus.failed);
    expect(session.state.snapshot.jobs.last.error, contains('回滚保存失败'));
    expect(session.state.error, isNotNull);
    final persisted = await storage.load();
    expect(persisted.assets.single, session.state.snapshot.assets.single);
    expect(await storage.readBytes(persisted.assets.single.storageKey), _png);
    repository.failWrites = false;
  });
}

final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=',
  ),
);

final class _Picker implements FileImportPort {
  final List<FileImportResult> results = [];
  Future<FileImportResult>? pending;
  int requests = 0;
  @override
  Future<FileImportResult> select(ImportKind kind) async {
    requests++;
    if (pending != null) return pending!;
    return results.removeAt(0);
  }
}

final class _Source implements ImportSource {
  _Source(
    this.name,
    this.bytes, {
    int? declaredLength,
    this.customStream,
    this.failClose = false,
  }) : byteLength = declaredLength ?? bytes.length;
  @override
  final String name;
  final List<int> bytes;
  @override
  final int byteLength;
  final Stream<List<int>>? customStream;
  bool closed = false;
  bool opened = false;
  final bool failClose;
  @override
  Stream<List<int>> openRead() {
    opened = true;
    return customStream ?? Stream.value(bytes);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (failClose) throw StateError('cleanup unavailable');
  }
}

final class _ControlledRepository implements WorkspaceRepository {
  _ControlledRepository({WorkspaceSnapshot initial = const WorkspaceSnapshot()})
    : snapshot = initial;
  WorkspaceSnapshot snapshot;
  final List<WorkspaceSnapshot> saved = [];
  @override
  int persistedVersion = 0;
  Completer<void>? gate;
  bool fail = false;
  bool block = true;
  @override
  Future<WorkspaceSnapshot> load() async => snapshot;
  @override
  Future<void> save(WorkspaceSnapshot value, {int? expectedVersion}) async {
    if (fail) throw StateError('disk full');
    if (block) {
      gate = Completer<void>();
      await gate!.future;
    }
    if (expectedVersion != null && expectedVersion != persistedVersion) {
      throw const WorkspaceConflict();
    }
    ++persistedVersion;
    saved.add(value);
    snapshot = value;
  }
}

final class _BlockingAssetStore implements AssetStore {
  _BlockingAssetStore(this.delegate);
  final AssetStore delegate;
  final gates = <Completer<void>>[];
  final entered = StreamController<int>.broadcast();
  @override
  Future<String> commit(String key) async {
    final gate = Completer<void>();
    gates.add(gate);
    entered.add(gates.length);
    await gate.future;
    return delegate.commit(key);
  }

  @override
  Future<String> stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  }) => delegate.stage(bytes, name: name, onBytes: onBytes);
  @override
  Future<void> abort(String key) => delegate.abort(key);
  @override
  Future<void> remove(String key) => delegate.remove(key);
  @override
  Stream<List<int>> read(String key) => delegate.read(key);
  @override
  Future<Uint8List> readBytes(String key) => delegate.readBytes(key);
  @override
  Future<void> cleanupStaging() => delegate.cleanupStaging();
}

final class _GatedNativeRepository implements WorkspaceRepository {
  _GatedNativeRepository(this.delegate);
  final WorkspaceRepository delegate;
  @override
  int get persistedVersion => delegate.persistedVersion;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool blockNext = false;
  bool failAfterBlockedSave = false;
  bool failWrites = false;
  @override
  Future<WorkspaceSnapshot> load() => delegate.load();
  @override
  Future<void> save(WorkspaceSnapshot snapshot, {int? expectedVersion}) async {
    if (failWrites) throw StateError('disk full during rollback');
    if (blockNext) {
      blockNext = false;
      entered.complete();
      await release.future;
      await delegate.save(snapshot, expectedVersion: expectedVersion);
      if (failAfterBlockedSave) failWrites = true;
      return;
    }
    await delegate.save(snapshot, expectedVersion: expectedVersion);
  }
}

final class _ThumbnailCleanupGate implements AssetStore {
  _ThumbnailCleanupGate(this.delegate, this.oldKey);
  final AssetStore delegate;
  final String oldKey;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> remove(String key) async {
    if (key == oldKey) {
      entered.complete();
      await release.future;
    }
    await delegate.remove(key);
  }

  @override
  Future<String> stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  }) => delegate.stage(bytes, name: name, onBytes: onBytes);
  @override
  Future<String> commit(String key) => delegate.commit(key);
  @override
  Future<void> abort(String key) => delegate.abort(key);
  @override
  Stream<List<int>> read(String key) => delegate.read(key);
  @override
  Future<Uint8List> readBytes(String key) => delegate.readBytes(key);
  @override
  Future<void> cleanupStaging() => delegate.cleanupStaging();
}
