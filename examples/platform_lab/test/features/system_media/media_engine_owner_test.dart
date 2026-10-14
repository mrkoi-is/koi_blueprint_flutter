import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/system_media/application/media_engine_owner.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';
import 'package:platform_lab/features/system_media/presentation/providers/system_media_providers.dart';
import 'package:platform_lab/features/system_media/presentation/system_media_page.dart';
import 'package:platform_lab/l10n/generated/app_localizations.dart';

import 'support.dart';

class _Factory implements MediaEngineFactory {
  _Factory(this.id, this.build);
  @override
  final String id;
  final Future<MediaEngine> Function() build;
  CapabilityAvailability availability =
      const CapabilityAvailability.available();
  Future<void>? waitForProbe;
  @override
  Future<CapabilityAvailability> probe() async {
    await waitForProbe;
    return availability;
  }

  @override
  Future<MediaEngine> create() => build();
}

class _FailedOpen extends FakeMediaEngine {
  @override
  Future<void> open(String uri) async =>
      throw StateError('decoder rejected file');
}

class _FailedPlayback extends FakeMediaEngine {
  bool reject = true;
  @override
  Future<void> play() async {
    if (reject) throw StateError('playback permission denied');
    await super.play();
  }
}

class _PartiallyFailedPause extends FakeMediaEngine {
  @override
  Future<void> pause() async {
    await super.pause();
    throw StateError('pause acknowledgement failed');
  }
}

void main() {
  test(
    'pause failure after native state changes restores previous playback',
    () async {
      final previous = _PartiallyFailedPause();
      final candidate = FakeMediaEngine();
      final owner = MediaEngineOwner([
        _Factory('old', () async => previous),
        _Factory('next', () async => candidate),
      ]);
      await owner.select('old');
      await owner.open('test://selected');
      await owner.seek(const Duration(seconds: 43));
      await owner.play();
      expect(await owner.select('next'), isFalse);
      expect(owner.selectedId, 'old');
      expect(previous.playing, isTrue);
      expect(previous.position, const Duration(seconds: 43));
      expect(previous.closed, isFalse);
      expect(candidate.closed, isTrue);
      expect(owner.error, contains('pause acknowledgement failed'));
      await owner.close();
    },
  );

  test(
    'explicit unavailable, unknown and failed candidates retain the old owner',
    () async {
      final old = FakeMediaEngine();
      final failed = _FailedOpen();
      final unavailable = _Factory('missing', () async => FakeMediaEngine())
        ..availability = const CapabilityAvailability.unavailable(
          'native library missing',
        );
      final owner = MediaEngineOwner([
        _Factory('old', () async => old),
        unavailable,
        _Factory('broken', () async => failed),
        _Factory(
          'throws',
          () async => throw StateError('initialization failed'),
        ),
      ]);
      expect(await owner.select('old'), isTrue);
      await owner.open('test://selected');
      await owner.seek(const Duration(seconds: 12));
      await owner.setVolume(.4);
      await owner.play();
      for (final id in ['missing', 'unknown', 'broken', 'throws']) {
        expect(await owner.select(id), isFalse);
        expect(owner.selectedId, 'old');
        expect(old.closed, isFalse);
        expect(owner.playing, isTrue);
        expect(owner.position, const Duration(seconds: 12));
        expect(owner.volume, .4);
        expect(owner.error, isNotNull);
      }
      expect(failed.closed, isTrue);
      expect(owner.availability['missing']!.reason, 'native library missing');
      await owner.close();
      expect(old.closed, isTrue);
    },
  );

  test('successful explicit switch restores state, closes old engine and serializes commands', () async {
    final old = FakeMediaEngine();
    final next = FakeMediaEngine();
    final gate = Completer<void>();
    final second = _Factory('second', () async => next)
      ..waitForProbe = gate.future;
    final owner = MediaEngineOwner([
      _Factory('first', () async => old),
      second,
    ]);
    await owner.select('first');
    await owner.open('test://selected');
    await owner.seek(const Duration(seconds: 12));
    await owner.setVolume(.4);
    await owner.play();
    final selection = owner.select('second');
    final seek = owner.seek(const Duration(seconds: 20));
    expect(old.closed, isFalse);
    gate.complete();
    expect(await selection, isTrue);
    await seek;
    expect(owner.selectedId, 'second');
    expect(old.closed, isTrue);
    expect(next.opens, 1);
    expect(next.position, const Duration(seconds: 20));
    expect(next.volume, .4);
    expect(next.playing, isTrue);
    await owner.close();
    await owner.close();
    expect(next.closed, isTrue);
  });

  testWidgets('visible probe failure keeps current playback available', (
    tester,
  ) async {
    final native = FakeMediaEngine();
    final factory = _Factory('media-kit', () async => native);
    final owner = MediaEngineOwner([factory]);
    await owner.select('media-kit');
    final controller = MediaSessionController(owner);
    await controller.open('test://selected', 'Selected file');
    await controller.play();
    SystemMediaRuntime.engines = owner;
    addTearDown(() async {
      SystemMediaRuntime.engines = null;
      await controller.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemMediaControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [
            KoiUiLocalizations.delegate,
            ...AppLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SystemMediaPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    factory.availability = const CapabilityAvailability.unavailable(
      'native library missing',
    );
    await tester.tap(find.text('Check and select engine'));
    await tester.pumpAndSettle();
    expect(find.text('native library missing'), findsWidgets);
    expect(find.text('Selected file'), findsOneWidget);
    expect(owner.selectedId, 'media-kit');
    expect(native.playing, isTrue);
    expect(native.closed, isFalse);
    // Dispose the listener and the queued owner in the Widget test's zone;
    // teardown runs outside FakeAsync and cannot drain that zone's queue.
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });
  testWidgets(
    'unavailable default still exposes the unprobed explicit alternative',
    (tester) async {
      final defaultFactory = _Factory(
        'media-kit',
        () async => FakeMediaEngine(),
      )..availability = const CapabilityAvailability.unavailable('mpv missing');
      final alternate = FakeMediaEngine();
      final owner = MediaEngineOwner([
        defaultFactory,
        _Factory('audioplayers', () async => alternate),
      ]);
      expect(await owner.select('media-kit'), isFalse);
      final controller = MediaSessionController(owner);
      await controller.stop();
      SystemMediaRuntime.engines = owner;
      addTearDown(() {
        SystemMediaRuntime.engines = null;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            systemMediaControllerProvider.overrideWithValue(controller),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [
              KoiUiLocalizations.delegate,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SystemMediaPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('mpv missing'), findsWidgets);
      expect(
        find.text('Not checked: select to initialize this engine'),
        findsOneWidget,
      );
      expect(
        find.text('Available: engine initialization succeeded'),
        findsNothing,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Check and select engine').last);
      await tester.pumpAndSettle();
      expect(owner.selectedId, 'audioplayers');
      expect(
        find.text('Available: engine initialization succeeded'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.close();
    },
  );
  testWidgets('transport shows a platform playback error and allows retry', (
    tester,
  ) async {
    final engine = _FailedPlayback();
    final controller = MediaSessionController(engine);
    await controller.open('test://selected', 'Selected file');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: MediaTransport(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.textContaining('playback permission denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
    engine.reject = false;
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.textContaining('playback permission denied'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });
}
