import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:workbench_app/features/workspace/application/media_playback.dart';
import 'package:workbench_app/features/workspace/data/media/media_frame_gate.dart';
import 'package:workbench_app/features/workspace/data/media/capture_video_frame.dart';

/// SDK adaptation only. Bootstrap supplies the presentation surface and removes
/// it by player identity after all SDK cleanup has been attempted.
final class MediaKitPlayback extends ChangeNotifier implements MediaPlayback {
  MediaKitPlayback({this._onClosed}) {
    _video = VideoController(_player);
    _frameGate = MediaFrameGate(_player);
    _subscriptions.add(
      _player.stream.position.listen((_) => notifyListeners()),
    );
    _subscriptions.add(
      _player.stream.duration.listen((_) => notifyListeners()),
    );
    _subscriptions.add(_player.stream.playing.listen((_) => notifyListeners()));
    _subscriptions.add(_player.stream.volume.listen((_) => notifyListeners()));
  }
  final Player _player = Player();
  late final VideoController _video;
  late final MediaFrameGate _frameGate;
  final void Function()? _onClosed;
  VideoController get videoController => _video;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _closing;
  @override
  bool get playing => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  double get volume => _player.state.volume;
  @override
  Stream<String> get errors => _player.stream.error;
  @override
  Future<void> open(String uri) async {
    _video;
    await _player.open(Media(uri), play: false);
  }

  @override
  Future<void> get firstFrame =>
      _frameGate.wait(_video.waitUntilFirstFrameRendered);
  @override
  Future<Uint8List?> screenshot() => captureVideoFrame(
    () => _player.screenshot(format: 'image/jpeg'),
    isActive: () => _closing == null,
  );
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double value) => _player.setVolume(value);
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    final failures = <Object>[];
    for (final close in <Future<void> Function()>[
      _frameGate.close,
      for (final subscription in _subscriptions) subscription.cancel,
      _player.dispose,
    ]) {
      try {
        await close();
      } catch (error) {
        failures.add(error);
      }
    }
    super.dispose();
    try {
      _onClosed?.call();
    } catch (error) {
      failures.add(error);
    }
    if (failures.isNotEmpty) {
      throw StateError('播放器清理失败：${failures.join('; ')}');
    }
  }
}
