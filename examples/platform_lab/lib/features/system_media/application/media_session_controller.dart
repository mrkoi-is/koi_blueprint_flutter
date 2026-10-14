import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';

/// The same commands serve in-app UI, mini view, and system transport controls.
/// This optional owner is separate from a workbench's pause-on-leave preview.
class MediaSessionController extends BaseAudioHandler with SeekHandler {
  MediaSessionController(this.engine, {this.activate}) {
    engine.addListener(_publish);
    _publish();
  }
  final MediaEngine engine;
  final Future<bool> Function()? activate;
  bool backgroundPlayback = false;
  bool _resumeAfterInterruption = false;
  bool _closed = false;
  String? selectedTitle;
  String? error;
  int _openGeneration = 0;
  Future<void>? _openQueue;

  Future<void> open(String uri, String title) {
    final generation = ++_openGeneration;
    _openQueue = (_openQueue ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => _open(uri, title, generation));
    return _openQueue!;
  }

  Future<void> _open(String uri, String title, int generation) async {
    if (_closed || generation != _openGeneration) return;
    try {
      await engine.pause();
      await engine.open(uri);
      if (_closed || generation != _openGeneration) return;
      selectedTitle = title;
      error = null;
      mediaItem.add(
        MediaItem(id: uri, title: title, duration: engine.duration),
      );
      _publish();
    } catch (failure) {
      error = '$failure';
      _publish();
      rethrow;
    }
  }

  void _publish() {
    if (_closed) return;
    final current = mediaItem.value;
    if (current != null && current.duration != engine.duration) {
      mediaItem.add(current.copyWith(duration: engine.duration));
    }
    playbackState.add(
      PlaybackState(
        controls: [
          engine.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0],
        processingState: selectedTitle == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: engine.playing,
        updatePosition: engine.position,
        speed: 1,
        errorMessage: error,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_closed || selectedTitle == null) return;
    _resumeAfterInterruption = false;
    await _command(() async {
      if (activate != null && !await activate!()) return;
      await engine.play();
    });
  }

  @override
  Future<void> pause() async {
    _resumeAfterInterruption = false;
    if (!_closed) await _command(engine.pause);
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_closed) {
      await _command(
        () => engine.seek(
          Duration(
            milliseconds: position.inMilliseconds.clamp(
              0,
              engine.duration.inMilliseconds,
            ),
          ),
        ),
      );
    }
  }

  Future<void> setVolume(double value) async {
    if (!_closed) await _command(() => engine.setVolume(value));
  }

  Future<void> _command(Future<void> Function() action) async {
    try {
      await action();
      error = null;
      _publish();
    } catch (failure) {
      error = '$failure';
      _publish();
      rethrow;
    }
  }

  Future<void> interrupt({required bool beginning}) async {
    if (_closed) return;
    if (beginning) {
      _resumeAfterInterruption = _resumeAfterInterruption || engine.playing;
      await engine.pause();
    } else if (_resumeAfterInterruption) {
      _resumeAfterInterruption = false;
      await play();
    }
  }

  Future<void> becameNoisy() => pause();
  Future<void> visibilityChanged(bool visible) async {
    if (!visible && !backgroundPlayback) await pause();
  }

  @override
  Future<void> stop() async {
    await pause();
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_openGeneration;
    engine.removeListener(_publish);
    try {
      await _openQueue;
    } catch (_) {
      /* Failure was already published. */
    }
    await engine.close();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }
}
