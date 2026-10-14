import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;

/// canplaythrough reports buffered data; the compositor callback reports pixels.
final class MediaFrameGate {
  MediaFrameGate(this._player);
  final Player _player;
  web.HTMLVideoElement? _element;
  int? _callback;
  int? _animation;
  StreamSubscription<web.Event>? _seekSubscription;
  Completer<void>? _pending;
  final _closedSignal = Completer<void>();
  bool _closed = false;

  Future<void> wait(Future<void> controllerReady) async {
    final elapsed = Stopwatch()..start();
    const deadline = Duration(seconds: 10);
    await Future.any<void>([
      controllerReady,
      _closedSignal.future.then((_) => throw StateError('视频已关闭')),
    ]).timeout(deadline);
    if (_closed) throw StateError('视频已关闭');
    final platform = _player.platform;
    if (platform is! WebPlayer) throw StateError('Web 视频解码器不可用');
    // WebPlayer exposes element on Web; its VM analyzer stub omits that member.
    // Check the public platform type before this single platform-only access.
    final element = (platform as dynamic).element as web.HTMLVideoElement;
    _element = element;
    final pending = Completer<void>();
    _pending = pending;
    void rendered(double timestamp, _FrameMetadata metadata) {
      _callback = null;
      if (_closed || pending.isCompleted) return;
      if (element.readyState >= web.HTMLMediaElement.HAVE_CURRENT_DATA &&
          element.videoWidth > 0 &&
          element.videoHeight > 0 &&
          metadata.presentedFrames > 0) {
        pending.complete();
      } else {
        _callback = element.requestVideoFrameCallback(rendered.toJS);
      }
    }

    bool decoded() =>
        !_closed &&
        !element.seeking &&
        element.readyState >= web.HTMLMediaElement.HAVE_CURRENT_DATA &&
        element.videoWidth > 0 &&
        element.videoHeight > 0;

    try {
      _callback = element.requestVideoFrameCallback(rendered.toJS);
      if (element.paused) {
        _seekSubscription = element.onSeeked.listen((_) {
          final previous = _animation;
          if (previous != null) web.window.cancelAnimationFrame(previous);
          _animation = web.window.requestAnimationFrame(
            ((double timestamp) {
              _animation = null;
              // Seeking within the same decoded frame may not schedule another
              // RVFC. seeked confirms decoder completion; the browser frame turn
              // makes those paused pixels available to canvas.drawImage.
              if (!pending.isCompleted && decoded()) pending.complete();
            }).toJS,
          );
        });
        // A paused browser can buffer without compositing. Seeking requests a
        // decoded frame without starting playback or changing audible volume.
        final current = element.currentTime;
        final duration = element.duration;
        final target = duration.isFinite && duration > 0
            ? current + 0.001 < duration
                  ? current + 0.001
                  : math.max(0, current - math.min(0.001, duration / 2))
            : current + 0.001;
        element.currentTime = target;
      }
      await pending.future.timeout(deadline - elapsed.elapsed);
    } finally {
      _pending = null;
      await _detach();
    }
  }

  Future<void> close() async {
    _closed = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('视频已关闭'));
    }
    await _detach();
  }

  Future<void> _detach() async {
    final callback = _callback;
    _callback = null;
    if (callback != null) _element?.cancelVideoFrameCallback(callback);
    final animation = _animation;
    _animation = null;
    if (animation != null) web.window.cancelAnimationFrame(animation);
    final subscription = _seekSubscription;
    _seekSubscription = null;
    await subscription?.cancel();
  }
}

extension type _FrameMetadata._(JSObject _) implements JSObject {
  external double get presentedFrames;
}
