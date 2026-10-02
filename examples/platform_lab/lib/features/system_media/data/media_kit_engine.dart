import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:koi_core/koi_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';

class MediaKitEngineFactory implements MediaEngineFactory {
  const MediaKitEngineFactory();
  @override
  String get id => 'media-kit';
  @override
  Future<CapabilityAvailability> probe() async {
    MediaEngine? engine;
    try {
      engine = await create();
      return const CapabilityAvailability.available();
    } catch (error) {
      return CapabilityAvailability.unavailable('$error', diagnostic: error);
    } finally {
      await engine?.close();
    }
  }

  @override
  Future<MediaEngine> create() async {
    MediaKit.ensureInitialized();
    final engine = MediaKitEngine();
    try {
      // Player construction can complete before native initialization. Waiting
      // for its handle verifies the bundled engine is actually loadable.
      await engine.player.handle;
      return engine;
    } catch (_) {
      await engine.close();
      rethrow;
    }
  }
}

class MediaKitEngine extends ChangeNotifier implements MediaEngine {
  MediaKitEngine({
    Player? player,
    this.operationTimeout = const Duration(seconds: 10),
  }) : player = player ?? Player() {
    for (final stream in <Stream<Object?>>[
      this.player.stream.playing,
      this.player.stream.position,
      this.player.stream.duration,
      this.player.stream.audioParams,
      this.player.stream.volume,
    ]) {
      _subscriptions.add(
        stream.listen((_) => _notify(), onError: _recordFailure),
      );
    }
    _subscriptions.add(
      this.player.stream.error.listen(_recordFailure, onError: _recordFailure),
    );
  }

  final Player player;
  final Duration operationTimeout;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _pendingChecks = <void Function()>{};
  Object? _failure;
  bool _loaded = false;
  bool _closed = false;
  Future<void>? _closing;

  void _notify() {
    for (final check in _pendingChecks.toList()) {
      check();
    }
    if (!_closed) notifyListeners();
  }

  void _recordFailure(Object error) {
    _failure = error;
    _notify();
  }

  void _checkOpen() {
    if (_closed) throw StateError('MediaKit engine is closed');
  }

  // media_kit command Futures acknowledge dispatch, not media loading or seek
  // completion. Observe the real Player state before the owner can commit a
  // replacement. Subscribe before issuing the command to retain fast events.
  Future<void> _confirm(
    String operation,
    Future<void> Function() command,
    bool Function() ready,
  ) async {
    _checkOpen();
    if (_pendingChecks.isNotEmpty) {
      throw StateError('A MediaKit operation is already pending');
    }
    if (_failure case final failure?) throw failure;
    final confirmed = Completer<void>();
    var commandReturned = false;
    void check() {
      if (confirmed.isCompleted) return;
      if (_closed) {
        confirmed.completeError(StateError('MediaKit engine is closed'));
      } else if (_failure case final failure?) {
        confirmed.completeError(failure);
      } else if (commandReturned && ready()) {
        confirmed.complete();
      }
    }

    _pendingChecks.add(check);
    final timer = Timer(operationTimeout, () {
      if (!confirmed.isCompleted) {
        confirmed.completeError(
          TimeoutException(
            'MediaKit $operation was not confirmed',
            operationTimeout,
          ),
        );
      }
    });
    try {
      // Also receive an error/close/timeout while native dispatch is pending.
      await Future.any<void>([command(), confirmed.future]);
      commandReturned = true;
      check();
      await confirmed.future;
    } catch (_) {
      if (!commandReturned) {
        // Dart cannot cancel a plugin Future. Retire this player if dispatch
        // itself has not returned, so late native results cannot be reused by
        // a later open/selection. close also bounds unresponsive disposal.
        try {
          await close();
        } catch (_) {
          // Preserve the original command/timeout failure.
        }
      }
      rethrow;
    } finally {
      timer.cancel();
      _pendingChecks.remove(check);
    }
  }

  @override
  bool get playing => !_closed && player.state.playing;
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;
  @override
  double get volume => player.state.volume / 100;

  @override
  Future<void> open(String uri) async {
    _checkOpen();
    if (_pendingChecks.isNotEmpty) {
      throw StateError('A MediaKit operation is already pending');
    }
    _loaded = false;
    _failure = null;
    await _confirm(
      'open',
      () async {
        // A previous source's duration/audio format is not evidence that the
        // new source is ready. Stop resets those public SDK fields first.
        await player.stop();
        _checkOpen();
        _failure = null;
        await player.open(Media(uri), play: false);
      },
      () => duration > Duration.zero || player.state.audioParams.format != null,
    );
    _checkOpen();
    _loaded = true;
  }

  @override
  Future<void> play() async {
    _checkOpen();
    if (!_loaded) throw StateError('No audio source has been opened');
    if (_failure case final failure?) throw failure;
    await player.play();
  }

  @override
  Future<void> pause() async {
    _checkOpen();
    await player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _checkOpen();
    if (!_loaded) throw StateError('No audio source has been opened');
    final maximum = duration > Duration.zero
        ? duration.inMicroseconds
        : position.inMicroseconds;
    final target = Duration(
      microseconds: position.inMicroseconds.clamp(0, maximum < 0 ? 0 : maximum),
    );
    await _confirm(
      'seek',
      () => player.seek(target),
      () => (this.position - target).abs() <= const Duration(milliseconds: 100),
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    _checkOpen();
    await player.setVolume(volume.clamp(0, 1) * 100);
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _notify();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await player.dispose().timeout(operationTimeout);
    } finally {
      super.dispose();
    }
  }
}
