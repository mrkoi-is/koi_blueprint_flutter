import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/application/media_playback.dart';

export 'package:workbench_app/features/workspace/application/media_playback.dart';

/// One selected-video owner for the entire workspace, independent of layout.
final class MediaPreviewSession extends ChangeNotifier {
  MediaPreviewSession({
    required this.workspace,
    required this.openSource,
    required this.encodeThumbnail,
    required this.createPlayback,
    this.thumbnailTimeout = const Duration(seconds: 10),
  }) {
    _workspaceSubscription = workspace.changes.listen((_) {
      final jobId = _thumbnailJobId;
      if (jobId != null && workspace.isJobCancelled(jobId)) {
        _interruptCapture();
      }
    });
  }
  final WorkspaceSession workspace;
  final PreviewSourceFactory openSource;
  final Future<Uint8List> Function(Uint8List) encodeThumbnail;
  final MediaPlaybackFactory createPlayback;
  final Duration thumbnailTimeout;
  late final StreamSubscription<WorkspaceState> _workspaceSubscription;
  final Map<String, Duration> _positions = {};
  MediaPlayback? playback;
  PreviewSource? _source;
  WorkspaceAsset? asset;
  bool loading = false;
  bool visible = false;
  String? error;
  int _generation = 0;
  bool _closed = false;
  Future<void> _queue = Future.value();
  Future<void>? _closing;
  StreamSubscription<String>? _errorSubscription;
  String? _thumbnailJobId;
  Completer<void>? _captureInterrupted;

  Future<void> select(WorkspaceAsset? next, {bool retryThumbnail = false}) {
    if (_closed) {
      return Future.value();
    }
    if (asset?.id == next?.id && playback != null && !retryThumbnail) {
      return _queue;
    }
    final generation = ++_generation;
    _interruptCapture();
    final jobId = _thumbnailJobId;
    if (jobId != null) {
      workspace.cancelJob(jobId);
    }
    _queue = _queue
        .catchError((Object _) {})
        .then((_) => _replace(next, generation, retryThumbnail))
        .catchError((Object failure) {
          if (_current(generation)) {
            loading = false;
            error = '视频资源操作失败：$failure';
            _notify();
          }
        });
    return _queue;
  }

  Future<void> _replace(
    WorkspaceAsset? next,
    int generation,
    bool retry,
  ) async {
    if (!_current(generation)) {
      return;
    }
    if (retry) {
      error = null;
      _notify();
    }
    if (asset?.id != next?.id || playback == null) {
      loading = true;
      error = null;
      _notify();
      await _dropPlayback();
      if (!_current(generation)) {
        return;
      }
      asset = next;
      if (next?.kind != MediaKind.video) {
        loading = false;
        _notify();
        return;
      }
      try {
        final source = await openSource(next!.storageKey);
        if (!_current(generation)) {
          await source.release();
          return;
        }
        _source = source;
        final player = createPlayback();
        playback = player;
        player.addListener(_notify);
        _errorSubscription = player.errors.listen((message) {
          if (!_closed && identical(playback, player)) {
            error = '视频预览失败：$message';
            _notify();
          }
        });
        _notify();
        await player.open(source.uri);
        if (!_current(generation)) {
          return;
        }
        final position = _positions[next.id];
        if (position != null) {
          await player.seek(position);
        }
        loading = false;
        _notify();
      } catch (failure) {
        if (_current(generation)) {
          loading = false;
          error = '视频预览失败：$failure';
          _notify();
        }
        await _dropPlayback();
        return;
      }
    }
    if (_current(generation) &&
        next?.kind == MediaKind.video &&
        (retry || next!.thumbnailStatus != ThumbnailStatus.ready)) {
      await _captureThumbnail(next!, generation);
    }
  }

  Future<void> _captureThumbnail(WorkspaceAsset current, int generation) async {
    final player = playback;
    if (player == null) {
      return;
    }
    final jobId = workspace.beginThumbnail(current.id);
    _thumbnailJobId = jobId;
    final interrupted = Completer<void>();
    _captureInterrupted = interrupted;
    try {
      final bytes = await Future.any<Uint8List?>([
        (() async {
          await player.firstFrame;
          return player.screenshot();
        })().timeout(thumbnailTimeout),
        interrupted.future.then((_) => throw const _PreviewInterrupted()),
      ]);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('视频首帧截图为空');
      }
      if (!_current(generation) || workspace.isJobCancelled(jobId)) {
        throw const _PreviewInterrupted();
      }
      final thumbnail = await encodeThumbnail(bytes);
      if (!_current(generation) || workspace.isJobCancelled(jobId)) {
        throw const _PreviewInterrupted();
      }
      await workspace.storeThumbnail(current.id, thumbnail, jobId: jobId);
    } on _PreviewInterrupted {
      try {
        await _dropPlayback();
      } finally {
        await workspace.finishCancelledThumbnail(jobId);
      }
      if (_current(generation)) {
        error = '缩略图作业已取消，可重新打开预览';
        _notify();
      }
    } catch (failure) {
      await workspace.failThumbnail(
        current.id,
        '视频缩略图失败：$failure',
        jobId: jobId,
      );
      if (_current(generation)) {
        error = '视频缩略图失败：$failure';
        _notify();
      }
    } finally {
      if (_thumbnailJobId == jobId) {
        _thumbnailJobId = null;
        _captureInterrupted = null;
      }
    }
  }

  Future<void> retryThumbnail(WorkspaceAsset selected) =>
      select(selected, retryThumbnail: true);

  /// Pause and finish capture work without disposing a usable preview owner.
  Future<void> prepareToClose() async {
    ++_generation;
    _interruptCapture();
    final id = _thumbnailJobId;
    if (id != null && !workspace.preparingToClose) workspace.cancelJob(id);
    await _queue;
    await pause();
  }

  Future<void> pause() async {
    await playback?.pause();
  }

  Future<void> setVisible(bool value) async {
    visible = value;
    if (!value) {
      await pause();
    }
  }

  Future<void> togglePlaying() async {
    final player = playback;
    if (player == null || !visible) {
      return;
    }
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration value) async {
    await playback?.seek(value);
  }

  Future<void> setVolume(double value) async {
    await playback?.setVolume(value.clamp(0, 100));
  }

  bool _current(int generation) => !_closed && generation == _generation;
  void _interruptCapture() {
    final value = _captureInterrupted;
    if (value != null && !value.isCompleted) {
      value.complete();
    }
  }

  void _notify() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> _dropPlayback() async {
    final player = playback;
    playback = null;
    final source = _source;
    _source = null;
    final subscription = _errorSubscription;
    _errorSubscription = null;
    final failures = <Object>[];
    if (player != null) {
      final id = asset?.id;
      if (id != null) {
        _positions[id] = player.position;
      }
      player.removeListener(_notify);
    }
    for (final close in <Future<void> Function()>[
      if (subscription != null) subscription.cancel,
      if (player != null) player.close,
      if (source != null) source.release,
    ]) {
      try {
        await close();
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('视频资源清理失败：${failures.join('; ')}');
    }
  }

  Future<void> disposeAsync() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    ++_generation;
    final jobId = _thumbnailJobId;
    if (jobId != null && !workspace.preparingToClose) {
      workspace.cancelJob(jobId);
    }
    _interruptCapture();
    final failures = <Object>[];
    for (final close in <Future<void> Function()>[
      () => _queue,
      _workspaceSubscription.cancel,
      _dropPlayback,
    ]) {
      try {
        await close();
      } catch (error) {
        failures.add(error);
      }
    }
    super.dispose();
    if (failures.isNotEmpty) {
      throw StateError('视频会话清理失败：${failures.join('; ')}');
    }
  }
}

class _PreviewInterrupted implements Exception {
  const _PreviewInterrupted();
}
