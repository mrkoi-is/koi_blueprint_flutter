import 'dart:async';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_lab/features/system_media/application/media_engine_owner.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/data/audioplayers_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';
import 'package:koi_core/koi_core.dart';

import 'support.dart';

// Exercise the real AudioPlayer Dart implementation against its public plugin
// boundary. These fixtures do not claim that a native decoder ran on this host.
class _Platform extends AudioplayersPlatformInterface {
  final events = <String, StreamController<AudioEvent>>{};
  final positions = <String, int>{};
  final sources = <({String url, bool? local})>[];
  final closed = <String>[];
  final resumed = <String>[];
  bool rejectInitialization = false;
  bool rejectCreate = false;
  bool rejectPosition = false;
  Completer<int?>? positionGate;
  bool rejectResume = false;
  bool rejectVolume = false;
  int creates = 0;
  @override
  Future<void> create(String playerId) async {
    if (rejectCreate) {
      throw MissingPluginException('audio backend not registered');
    }
    creates++;
    events[playerId] = StreamController<AudioEvent>.broadcast();
    positions[playerId] = 0;
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      events[playerId]!.stream;
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {
    expect(releaseMode, ReleaseMode.stop);
    if (rejectInitialization) throw PlatformException(code: 'backend_missing');
  }

  @override
  Future<void> setVolume(String playerId, double volume) async {
    if (rejectVolume) throw PlatformException(code: 'volume_failed');
  }

  @override
  Future<void> pause(String playerId) async {}
  @override
  Future<void> stop(String playerId) async {}
  @override
  Future<void> release(String playerId) async {}
  @override
  Future<void> resume(String playerId) async {
    if (rejectResume) throw PlatformException(code: 'play_failed');
    resumed.add(playerId);
  }

  @override
  Future<void> seek(String playerId, Duration position) async {
    positions[playerId] = position.inMilliseconds;
    events[playerId]!.add(
      const AudioEvent(eventType: AudioEventType.seekComplete),
    );
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    if (rejectPosition) throw PlatformException(code: 'position_failed');
    if (positionGate case final gate?) return gate.future;
    return positions[playerId];
  }

  @override
  Future<int?> getDuration(String playerId) async => 120000;
  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    sources.add((url: url, local: isLocal));
    positions[playerId] = 0;
    events[playerId]!.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> dispose(String playerId) async {
    closed.add(playerId);
    await events.remove(playerId)!.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _GlobalPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _ExistingFactory implements MediaEngineFactory {
  _ExistingFactory(this.engine);
  final MediaEngine engine;
  @override
  String get id => 'existing';
  @override
  Future<CapabilityAvailability> probe() async =>
      const CapabilityAvailability.available();
  @override
  Future<MediaEngine> create() async => engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late AudioplayersPlatformInterface original;
  late GlobalAudioplayersPlatformInterface originalGlobal;
  setUp(() {
    original = AudioplayersPlatformInterface.instance;
    originalGlobal = GlobalAudioplayersPlatformInterface.instance;
    platform = _Platform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance = _GlobalPlatform();
  });
  tearDown(() {
    AudioplayersPlatformInterface.instance = original;
    GlobalAudioplayersPlatformInterface.instance = originalGlobal;
    expect(
      platform.events,
      isEmpty,
      reason: 'Every created platform player must be disposed',
    );
  });

  test(
    'probe awaits plugin acknowledgement and releases its real Dart player',
    () async {
      const factory = AudioplayersEngineFactory();
      expect((await factory.probe()).isAvailable, isTrue);
      expect(platform.creates, 1);
      expect(platform.closed, hasLength(1));
      platform.rejectInitialization = true;
      final unavailable = await factory.probe();
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.reason, contains('backend_missing'));
      expect(platform.closed, hasLength(2));
    },
  );

  test(
    'source mapping, playback, seek, volume and completion reach the plugin',
    () async {
      final engine = await const AudioplayersEngineFactory().create();
      final uri = kIsWeb ? 'blob:https://example.test/audio' : '/tmp/audio.wav';
      await engine.open(uri);
      expect(platform.sources.single, (url: uri, local: !kIsWeb));
      expect(engine.duration, const Duration(minutes: 2));
      expect(engine.playing, isFalse);
      await engine.play();
      expect(engine.playing, isTrue);
      await engine.seek(const Duration(seconds: 9));
      expect(engine.position, const Duration(seconds: 9));
      await engine.setVolume(.3);
      expect(engine.volume, .3);
      platform.rejectVolume = true;
      await expectLater(
        engine.setVolume(.8),
        throwsA(isA<PlatformException>()),
      );
      expect(
        engine.volume,
        .3,
        reason: 'Failed platform writes do not publish false state',
      );
      platform.rejectVolume = false;
      await engine.setVolume(2);
      expect(engine.volume, 1);
      await engine.pause();
      expect(engine.playing, isFalse);
      platform.events.values.single.add(
        const AudioEvent(
          eventType: AudioEventType.duration,
          duration: Duration(seconds: 30),
        ),
      );
      platform.events.values.single.add(
        const AudioEvent(eventType: AudioEventType.complete),
      );
      await Future<void>.delayed(Duration.zero);
      expect(engine.duration, const Duration(seconds: 30));
      expect(engine.playing, isFalse);
      await engine.close();
      await engine.close();
      expect(platform.closed, hasLength(1));
      await expectLater(engine.play(), throwsStateError);
    },
  );

  test(
    'file URI, Windows path and HTTP URL remain distinct source types',
    () async {
      final engine = await const AudioplayersEngineFactory().create();
      if (!kIsWeb) {
        await engine.open('file:///tmp/audio%20one.wav');
        expect(platform.sources.last, (url: '/tmp/audio one.wav', local: true));
        await engine.open(r'C:\Music\audio.wav');
        expect(platform.sources.last, (
          url: r'C:\Music\audio.wav',
          local: true,
        ));
      }
      await engine.open('https://example.test/audio.wav');
      expect(platform.sources.last, (
        url: 'https://example.test/audio.wav',
        local: false,
      ));
      await engine.close();
    },
  );

  test(
    'empty-source selection never seeks an unprepared native player',
    () async {
      final old = FakeMediaEngine();
      final owner = MediaEngineOwner([
        _ExistingFactory(old),
        const AudioplayersEngineFactory(),
      ]);
      await owner.select('existing');
      expect(await owner.select('audioplayers'), isTrue);
      expect(platform.sources, isEmpty);
      expect(old.closed, isTrue);
      await expectLater(owner.seek(Duration.zero), throwsStateError);
      await owner.close();
    },
  );

  test('explicit switch transfers opened source and playback through the independent adapter', () async {
    final old = FakeMediaEngine();
    final owner = MediaEngineOwner([
      _ExistingFactory(old),
      const AudioplayersEngineFactory(),
    ]);
    await owner.select('existing');
    await owner.open('https://example.test/track.wav');
    await owner.seek(const Duration(seconds: 14));
    await owner.setVolume(.25);
    await owner.play();
    expect(await owner.select('audioplayers'), isTrue);
    expect(owner.selectedId, 'audioplayers');
    expect(owner.position, const Duration(seconds: 14));
    expect(owner.volume, .25);
    expect(owner.playing, isTrue);
    expect(old.closed, isTrue);
    expect(platform.resumed, hasLength(1));
    await owner.close();
  });

  test('candidate playback failure closes candidate and resumes the previous owner', () async {
    final old = FakeMediaEngine();
    final owner = MediaEngineOwner([
      _ExistingFactory(old),
      const AudioplayersEngineFactory(),
    ]);
    await owner.select('existing');
    await owner.open('https://example.test/track.wav');
    await owner.seek(const Duration(seconds: 14));
    await owner.play();
    platform.rejectResume = true;
    expect(await owner.select('audioplayers'), isFalse);
    expect(owner.selectedId, 'existing');
    expect(owner.error, contains('play_failed'));
    expect(old.playing, isTrue);
    expect(old.position, const Duration(seconds: 14));
    expect(old.closed, isFalse);
    expect(
      platform.closed,
      hasLength(2),
      reason: 'Probe and failed candidate both release their players',
    );
    await owner.close();
  });
  test(
    'missing plugin is unavailable and does not fabricate a native handle',
    () async {
      platform.rejectCreate = true;
      final result = await const AudioplayersEngineFactory().probe();
      expect(result.isAvailable, isFalse);
      expect(result.reason, contains('audio backend not registered'));
      expect(platform.creates, 0);
    },
  );

  test('position polling retries transient failures and close ignores an in-flight read', () async {
    final engine = await const AudioplayersEngineFactory().create();
    await engine.open('https://example.test/track.wav');
    await engine.play();
    platform.rejectPosition = true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(engine.playing, isTrue);
    platform.rejectPosition = false;
    platform.positions[platform.events.keys.single] = 9000;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(engine.position, const Duration(seconds: 9));
    await engine.play();
    await engine.open('https://example.test/retry.wav');
    final gate = Completer<int?>();
    platform.positionGate = gate;
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await engine.close();
    gate.complete(24000);
    await Future<void>.delayed(Duration.zero);
    expect(engine.position, Duration.zero);
    expect(platform.closed, hasLength(1));
  });
  test(
    'session publishes actual playback rejection and clears it on retry',
    () async {
      final engine = await const AudioplayersEngineFactory().create();
      final session = MediaSessionController(engine);
      await session.open('https://example.test/track.wav', 'Track');
      platform.rejectResume = true;
      await expectLater(session.play(), throwsA(isA<PlatformException>()));
      expect(session.error, contains('play_failed'));
      expect(session.playbackState.value.errorMessage, contains('play_failed'));
      expect(engine.playing, isFalse);
      platform.rejectResume = false;
      await session.play();
      expect(session.error, isNull);
      expect(session.playbackState.value.playing, isTrue);
      await session.close();
    },
  );
  test(
    'asynchronous decoder errors are handled and reopening allows recovery',
    () async {
      final engine = await const AudioplayersEngineFactory().create();
      await engine.open('https://example.test/track.wav');
      platform.events.values.single.addError(
        PlatformException(code: 'decoder_failed'),
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(engine.play(), throwsA(isA<PlatformException>()));
      await engine.open('https://example.test/retry.wav');
      await engine.play();
      expect(engine.playing, isTrue);
      await engine.close();
    },
  );
}
