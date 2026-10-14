import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:platform_lab/features/system_media/application/media_engine_owner.dart';
import 'package:platform_lab/features/system_media/data/media_kit_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';

import 'support.dart';

// The public Player wrapper is real. The plugin boundary deliberately returns
// command acknowledgements before loading/position events, as observed in the
// v6 mounted macOS application. This is not native decoding evidence.
class _DelayedBackend extends PlatformPlayer {
  _DelayedBackend() : super(configuration: const PlayerConfiguration());
  bool autoLoad = false;
  bool autoSeek = false;
  bool closed = false;
  int stops = 0;
  Completer<void>? openGate;
  Completer<void>? disposeGate;
  int seekCalls = 0;
  int playCalls = 0;
  Duration? requested;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    await openGate?.future;
    if (autoLoad && !closed) loaded();
  }

  @override
  Future<void> stop() async {
    stops++;
    state = PlayerState();
    durationController.add(Duration.zero);
    positionController.add(Duration.zero);
    audioParamsController.add(state.audioParams);
  }

  void loaded() {
    state = state.copyWith(duration: const Duration(minutes: 2));
    durationController.add(state.duration);
  }

  void positioned(Duration position) {
    state = state.copyWith(position: position);
    positionController.add(position);
  }

  void fail(String message) => errorController.add(message);

  void readyUnknownDuration() {
    state = state.copyWith(audioParams: const AudioParams(format: 's16'));
    audioParamsController.add(state.audioParams);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    requested = position;
    if (autoSeek) positioned(position);
  }

  @override
  Future<void> play() async {
    playCalls++;
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    volumeController.add(volume);
  }

  @override
  Future<void> dispose() async {
    closed = true;
    await disposeGate?.future;
    await super.dispose();
  }
}

class _Factory implements MediaEngineFactory {
  _Factory(this.id, this.engine);
  @override
  final String id;
  final MediaEngine engine;
  @override
  Future<MediaEngine> create() async => engine;
  @override
  Future<CapabilityAvailability> probe() async =>
      const CapabilityAvailability.available();
}

Future<void> _events() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'reopen clears previous metadata and rejects overlapping operations',
    () async {
      final backend = _DelayedBackend()..autoLoad = true;
      final engine = MediaKitEngine(player: Player(platformPlayer: backend));
      try {
        await engine.open('test://first');
        backend.autoLoad = false;
        var completed = false;
        final opening = engine
            .open('test://second')
            .then((_) => completed = true);
        await _events();
        expect(backend.stops, 2);
        expect(engine.duration, Duration.zero);
        await expectLater(engine.open('test://overlap'), throwsStateError);
        backend.positioned(const Duration(seconds: 43));
        await _events();
        expect(
          completed,
          isFalse,
          reason: 'Old position is not loaded metadata',
        );
        backend.loaded();
        await opening;
      } finally {
        await engine.close();
      }
    },
  );

  test(
    'asynchronous decoder error fails loading and a fresh open can retry',
    () async {
      final backend = _DelayedBackend();
      final engine = MediaKitEngine(player: Player(platformPlayer: backend));
      try {
        final failure = expectLater(
          engine.open('test://broken'),
          throwsA('decoder failed'),
        );
        await _events();
        backend.fail('decoder failed');
        await failure;
        await expectLater(engine.play(), throwsStateError);
        backend.autoLoad = true;
        await engine.open('test://valid');
        await engine.play();
        expect(engine.playing, isTrue);
      } finally {
        await engine.close();
      }
    },
  );

  test(
    'timeout retires pending command and late completion cannot reopen it',
    () async {
      final gate = Completer<void>();
      final backend = _DelayedBackend()..openGate = gate;
      final engine = MediaKitEngine(
        player: Player(platformPlayer: backend),
        operationTimeout: const Duration(milliseconds: 30),
      );
      await expectLater(
        engine.open('test://slow'),
        throwsA(isA<TimeoutException>()),
      );
      expect(backend.closed, isTrue);
      gate.complete();
      await _events();
      await expectLater(engine.open('test://new-generation'), throwsStateError);
      await expectLater(engine.play(), throwsStateError);
      await engine.close();
    },
  );

  test(
    'close cancels pending confirmation and ignores late native completion',
    () async {
      final gate = Completer<void>();
      final backend = _DelayedBackend()..openGate = gate;
      final engine = MediaKitEngine(player: Player(platformPlayer: backend));
      final failed = expectLater(engine.open('test://slow'), throwsStateError);
      await _events();
      await engine.close();
      await failed;
      gate.complete();
      await _events();
      await engine.close();
      expect(backend.closed, isTrue);
      await expectLater(engine.seek(Duration.zero), throwsStateError);
    },
  );

  test(
    'unresponsive native disposal is bounded and late completion is consumed',
    () async {
      final gate = Completer<void>();
      final backend = _DelayedBackend()..disposeGate = gate;
      final engine = MediaKitEngine(
        player: Player(platformPlayer: backend),
        operationTimeout: const Duration(milliseconds: 30),
      );
      await expectLater(engine.close(), throwsA(isA<TimeoutException>()));
      gate.complete();
      await _events();
      await expectLater(engine.play(), throwsStateError);
    },
  );

  test('unknown-duration audio and zero seek remain bounded', () async {
    final backend = _DelayedBackend();
    final engine = MediaKitEngine(
      player: Player(platformPlayer: backend),
      operationTimeout: const Duration(milliseconds: 30),
    );
    try {
      final opening = engine.open('test://stream');
      await _events();
      backend.readyUnknownDuration();
      await opening;
      await engine.seek(Duration.zero);
      expect(backend.requested, Duration.zero);
      await expectLater(
        engine.seek(const Duration(seconds: 9)),
        throwsA(isA<TimeoutException>()),
      );
      expect(engine.position, Duration.zero);
    } finally {
      await engine.close();
    }
  });

  test(
    'open waits for loaded metadata after command acknowledgement',
    () async {
      final backend = _DelayedBackend();
      final engine = MediaKitEngine(player: Player(platformPlayer: backend));
      try {
        var completed = false;
        final opening = engine
            .open('test://audio')
            .then((_) => completed = true);
        await _events();
        expect(completed, isFalse);
        backend.loaded();
        await opening;
        expect(engine.duration, const Duration(minutes: 2));
        expect(engine.playing, isFalse);
      } finally {
        await engine.close();
      }
    },
  );

  test(
    'seek waits for observed target instead of command acknowledgement',
    () async {
      final backend = _DelayedBackend()..autoLoad = true;
      final engine = MediaKitEngine(player: Player(platformPlayer: backend));
      try {
        await engine.open('test://audio');
        var completed = false;
        final seeking = engine
            .seek(const Duration(seconds: 43))
            .then((_) => completed = true);
        await _events();
        expect(backend.requested, const Duration(seconds: 43));
        expect(completed, isFalse);
        backend.positioned(const Duration(seconds: 43));
        await seeking;
        await engine.play();
        expect(engine.position, const Duration(seconds: 43));
      } finally {
        await engine.close();
      }
    },
  );

  test(
    'playing migration keeps old engine until candidate position is confirmed',
    () async {
      final previous = FakeMediaEngine();
      final backend = _DelayedBackend();
      final next = MediaKitEngine(player: Player(platformPlayer: backend));
      final owner = MediaEngineOwner([
        _Factory('old', previous),
        _Factory('media-kit', next),
      ]);
      try {
        await owner.select('old');
        await owner.open('test://audio');
        await owner.seek(const Duration(seconds: 43));
        await owner.setVolume(.2);
        await owner.play();
        final switching = owner.select('media-kit');
        await _events();
        expect(previous.closed, isFalse);
        expect(previous.playing, isTrue);
        expect(backend.seekCalls, 0);
        previous.position = const Duration(seconds: 44);
        backend.loaded();
        await _events();
        expect(owner.selectedId, 'old');
        expect(previous.closed, isFalse);
        expect(previous.playing, isFalse);
        expect(backend.requested, const Duration(seconds: 44));
        expect(backend.playCalls, 0);
        backend.positioned(const Duration(seconds: 44));
        expect(await switching, isTrue);
        expect(previous.closed, isTrue);
        expect(owner.position, const Duration(seconds: 44));
        expect(owner.volume, .2);
        expect(owner.playing, isTrue);
      } finally {
        await owner.close();
      }
    },
  );

  test(
    'unconfirmed native seek times out and resumes the previous owner',
    () async {
      final previous = FakeMediaEngine();
      final backend = _DelayedBackend()..autoLoad = true;
      final next = MediaKitEngine(
        player: Player(platformPlayer: backend),
        operationTimeout: const Duration(milliseconds: 30),
      );
      final owner = MediaEngineOwner([
        _Factory('old', previous),
        _Factory('media-kit', next),
      ]);
      try {
        await owner.select('old');
        await owner.open('test://audio');
        await owner.seek(const Duration(seconds: 43));
        await owner.play();
        expect(await owner.select('media-kit'), isFalse);
        expect(owner.selectedId, 'old');
        expect(previous.closed, isFalse);
        expect(previous.playing, isTrue);
        expect(owner.position, const Duration(seconds: 43));
        expect(backend.closed, isTrue);
        expect(owner.error, contains('seek'));
      } finally {
        await owner.close();
      }
    },
  );
}
