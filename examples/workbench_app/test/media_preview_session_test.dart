import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_preview_session.dart';

import 'presentation_support.dart';

void main() {
  const first = WorkspaceAsset(
    id: 'first',
    name: 'first.mp4',
    kind: MediaKind.video,
    byteLength: 10,
    storageKey: 'first',
    thumbnailStatus: ThumbnailStatus.ready,
  );
  const second = WorkspaceAsset(
    id: 'second',
    name: 'second.mp4',
    kind: MediaKind.video,
    byteLength: 20,
    storageKey: 'second',
    thumbnailStatus: ThumbnailStatus.ready,
  );

  Future<WorkspaceSession> workspace(MemoryStorage storage) async {
    final session = WorkspaceSession(
      repository: storage.repository,
      assetStore: storage.assetStore,
      fileImportPort: CancelImport(),
    );
    await session.initialize();
    return session;
  }

  test(
    'same asset keeps player identity; old player closes before new is created',
    () async {
      final storage = MemoryStorage(
        const WorkspaceSnapshot(assets: [first, second]),
      );
      final session = await workspace(storage);
      final players = <FakePlayback>[];
      final events = <String>[];
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (key) async => PreviewSource(
          uri: 'test://$key',
          release: () async {
            events.add('release:$key');
          },
        ),
        encodeThumbnail: (bytes) async => bytes,
        createPlayback: () {
          events.add('create:${players.length}');
          final player = FakePlayback(
            onClose: () async {
              events.add('close:${players.indexOf(players.first)}');
            },
          );
          players.add(player);
          return player;
        },
      );
      await preview.select(first);
      final player = preview.playback;
      await preview.select(first);
      expect(preview.playback, same(player));
      expect(players, hasLength(1));
      await preview.setVisible(true);
      await preview.togglePlaying();
      expect(players.first.playing, isTrue);
      await preview.setVisible(false);
      expect(players.first.playing, isFalse);
      await preview.setVisible(true);
      expect(players.first.playing, isFalse);
      await preview.setVolume(35);
      expect(players.first.volume, 35);
      await preview.select(second);
      expect(events, ['create:0', 'close:0', 'release:first', 'create:1']);
      final disposal = preview.disposeAsync();
      expect(preview.disposeAsync(), same(disposal));
      await disposal;
      await session.dispose();
    },
  );

  test(
    'null screenshot is explicit failure and retry persists a thumbnail',
    () async {
      const asset = WorkspaceAsset(
        id: 'video',
        name: 'video.mp4',
        kind: MediaKind.video,
        byteLength: 10,
        storageKey: 'video',
      );
      final storage = MemoryStorage(const WorkspaceSnapshot(assets: [asset]));
      final session = await workspace(storage);
      final player = FakePlayback()..screenshotBytes = null;
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (_) async =>
            PreviewSource(uri: 'test://video', release: () async {}),
        encodeThumbnail: (bytes) async => Uint8List.fromList(bytes),
        createPlayback: () => player,
      );
      await preview.select(asset);
      expect(
        session.state.snapshot.assets.single.thumbnailStatus,
        ThumbnailStatus.failed,
      );
      expect(preview.error, contains('截图为空'));
      player.screenshotBytes = Uint8List.fromList([1, 2, 3]);
      await preview.retryThumbnail(session.state.snapshot.assets.single);
      expect(
        session.state.snapshot.assets.single.thumbnailStatus,
        ThumbnailStatus.ready,
      );
      expect(session.state.snapshot.assets.single.thumbnailKey, isNotNull);
      expect(session.state.snapshot.jobs.last.status, JobStatus.succeeded);
      expect(player.screenshots, 2);
      await preview.disposeAsync();
      await session.dispose();
    },
  );

  test(
    'cancel releases player/source and a late screenshot cannot publish',
    () async {
      const asset = WorkspaceAsset(
        id: 'video',
        name: 'video.mp4',
        kind: MediaKind.video,
        byteLength: 10,
        storageKey: 'video',
      );
      final storage = MemoryStorage(const WorkspaceSnapshot(assets: [asset]));
      final session = await workspace(storage);
      final player = FakePlayback()
        ..screenshotPending = Completer<Uint8List?>();
      var releases = 0;
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (_) async => PreviewSource(
          uri: 'test://video',
          release: () async {
            ++releases;
          },
        ),
        encodeThumbnail: (bytes) async => bytes,
        createPlayback: () => player,
      );
      final selecting = preview.select(asset);
      while (session.state.snapshot.jobs.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      session.cancelJob(session.state.snapshot.jobs.single.id);
      await selecting;
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelled);
      expect(player.closes, 1);
      expect(releases, 1);
      player.screenshotPending!.complete(Uint8List.fromList([9]));
      await Future<void>.delayed(Duration.zero);
      expect(session.state.snapshot.assets.single.thumbnailKey, isNull);
      expect(storage.assetStore.values, isEmpty);
      await preview.disposeAsync();
      await session.dispose();
    },
  );

  test(
    'thumbnail deadline is a failed job with retry, not invented progress',
    () async {
      const asset = WorkspaceAsset(
        id: 'video',
        name: 'video.mp4',
        kind: MediaKind.video,
        byteLength: 10,
        storageKey: 'video',
      );
      final storage = MemoryStorage(const WorkspaceSnapshot(assets: [asset]));
      final session = await workspace(storage);
      final player = FakePlayback()
        ..screenshotPending = Completer<Uint8List?>();
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (_) async =>
            PreviewSource(uri: 'test://video', release: () async {}),
        encodeThumbnail: (bytes) async => bytes,
        createPlayback: () => player,
        thumbnailTimeout: const Duration(milliseconds: 5),
      );
      await preview.select(asset);
      expect(session.state.snapshot.jobs.single.status, JobStatus.failed);
      expect(session.state.snapshot.jobs.single.processedBytes, 0);
      expect(preview.error, contains('TimeoutException'));
      player.screenshotPending!.complete(null);
      await preview.disposeAsync();
      await session.dispose();
    },
  );

  test('lease is released even if disposing player fails', () async {
    final storage = MemoryStorage(const WorkspaceSnapshot(assets: [first]));
    final session = await workspace(storage);
    var releases = 0;
    final preview = MediaPreviewSession(
      workspace: session,
      openSource: (_) async => PreviewSource(
        uri: 'test://video',
        release: () async {
          ++releases;
        },
      ),
      encodeThumbnail: (bytes) async => bytes,
      createPlayback: () => FakePlayback(
        onClose: () async {
          throw StateError('dispose failed');
        },
      ),
    );
    await preview.select(first);
    await expectLater(preview.disposeAsync(), throwsStateError);
    expect(releases, 1);
    await session.dispose();
  });

  test(
    'cancellation finishes its job even when player disposal reports failure',
    () async {
      final asset = first.copyWith(thumbnailStatus: ThumbnailStatus.none);
      final storage = MemoryStorage(WorkspaceSnapshot(assets: [asset]));
      final session = await workspace(storage);
      var releases = 0;
      final player = FakePlayback(
        onClose: () async {
          throw StateError('dispose failed');
        },
      )..screenshotPending = Completer<Uint8List?>();
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (_) async => PreviewSource(
          uri: 'test://video',
          release: () async {
            ++releases;
          },
        ),
        encodeThumbnail: (bytes) async => bytes,
        createPlayback: () => player,
      );
      final selecting = preview.select(asset);
      while (session.state.snapshot.jobs.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      session.cancelJob(session.state.snapshot.jobs.single.id);
      await selecting;
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelled);
      expect(releases, 1);
      expect(preview.error, contains('清理失败'));
      player.screenshotPending!.complete(null);
      await preview.disposeAsync();
      await session.dispose();
    },
  );
}
