import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:koi_core/koi_core.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';

/// Independent platform backend: AVPlayer, MediaPlayer, Media Foundation,
/// GStreamer, or browser audio. OS transport remains owned by the host.
class AudioplayersEngineFactory implements MediaEngineFactory {
  const AudioplayersEngineFactory();

  @override
  String get id => 'audioplayers';

  @override
  Future<CapabilityAvailability> probe() async {
    try {
      final engine = await create();
      await engine.close();
      return const CapabilityAvailability.available();
    } catch (error) {
      return CapabilityAvailability.unavailable('$error', diagnostic: error);
    }
  }

  @override
  Future<MediaEngine> create() async {
    final engine = AudioplayersEngine._(AudioPlayer());
    try {
      // Both commands wait for the real platform instance and acknowledgement.
      // A successful probe verifies initialization, not a particular codec or
      // browser autoplay permission. Opening/playing still reports its errors.
      await engine._player.setReleaseMode(ReleaseMode.stop);
      await engine.setVolume(1);
      return engine;
    } catch (_) {
      try {
        await engine.close();
      } catch (_) {
        // Preserve the initialization failure if plugin teardown also fails.
      }
      rethrow;
    }
  }
}

class AudioplayersEngine extends ChangeNotifier implements MediaEngine {
  AudioplayersEngine._(this._player) {
    _player.positionUpdater = TimerPositionUpdater(
      // Timer updates also work while the Flutter view is hidden.
      interval: const Duration(milliseconds: 200),
      getPosition: _readPosition,
    );
    _subscriptions.addAll([
      _player.onPlayerStateChanged.listen(
        (_) => _notify(),
        onError: _recordFailure,
      ),
      _player.onDurationChanged.listen((value) {
        _duration = value;
        _notify();
      }, onError: _recordFailure),
      _player.onPositionChanged.listen((value) {
        _position = value;
        _notify();
      }, onError: _recordFailure),
    ]);
  }

  final AudioPlayer _player;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1;
  Object? _failure;
  bool _loaded = false;
  bool _closed = false;
  Future<void>? _closing;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _recordFailure(Object error) {
    _failure = error;
    _notify();
  }

  Future<Duration?> _readPosition() async {
    if (_closed) return null;
    try {
      final value = await _player.getCurrentPosition();
      return _closed ? null : value;
    } catch (_) {
      // Polling is best effort. Retain the last position and retry next tick;
      // a temporary position-query failure must not disable playback.
      return null;
    }
  }

  void _checkOpen() {
    if (_closed) throw StateError('Audio engine is closed');
  }

  @override
  bool get playing => !_closed && _player.state == PlayerState.playing;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get volume => _volume;

  @override
  Future<void> open(String uri) async {
    _checkOpen();
    await _player.pause();
    _loaded = false;
    _failure = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    final parsed = Uri.parse(uri);
    final windowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(uri);
    final Source source;
    if (!kIsWeb && (parsed.scheme.isEmpty || windowsPath)) {
      source = DeviceFileSource(uri);
    } else if (!kIsWeb && parsed.scheme == 'file') {
      source = DeviceFileSource(parsed.toFilePath());
    } else {
      source = UrlSource(uri);
    }
    await _player.setSource(source);
    _duration = await _player.getDuration() ?? _duration;
    _position = await _readPosition() ?? Duration.zero;
    _loaded = true;
    _notify();
  }

  @override
  Future<void> play() async {
    _checkOpen();
    if (!_loaded) throw StateError('No audio source has been opened');
    if (_failure case final failure?) throw failure;
    await _player.resume();
    _notify();
  }

  @override
  Future<void> pause() async {
    _checkOpen();
    await _player.pause();
    _notify();
  }

  @override
  Future<void> seek(Duration position) async {
    _checkOpen();
    // AVPlayer has no seek completion event until a source is prepared.
    if (!_loaded) throw StateError('No audio source has been opened');
    final maximum = _duration > Duration.zero ? _duration : position;
    final target = Duration(
      microseconds: position.inMicroseconds.clamp(
        0,
        maximum.inMicroseconds < 0 ? 0 : maximum.inMicroseconds,
      ),
    );
    await _player.seek(target);
    _position = target;
    _notify();
  }

  @override
  Future<void> setVolume(double volume) async {
    _checkOpen();
    final value = volume.clamp(0.0, 1.0);
    await _player.setVolume(value);
    _volume = value;
    _notify();
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await _player.dispose();
    } finally {
      super.dispose();
    }
  }
}
