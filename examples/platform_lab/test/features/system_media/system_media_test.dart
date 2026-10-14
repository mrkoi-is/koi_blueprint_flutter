import 'package:flutter_test/flutter_test.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';

import 'support.dart';

void main() {
  test('media interruption and user pause use a single engine and never resume unexpectedly', () async {
    final engine = FakeMediaEngine();
    final media = MediaSessionController(engine);
    await media.open('test://song', 'Song');
    await media.play();
    await media.seek(const Duration(seconds: 25));
    await media.interrupt(beginning: true);
    expect(engine.playing, isFalse);
    await media.interrupt(beginning: false);
    expect(engine.playing, isTrue);
    await media.interrupt(beginning: true);
    await media.pause();
    await media.interrupt(beginning: false);
    expect(engine.playing, isFalse);
    await media.play();
    await media.becameNoisy();
    expect(engine.playing, isFalse);
    await media.play();
    await media.visibilityChanged(false);
    expect(engine.playing, isFalse);
    media.backgroundPlayback = true;
    await media.play();
    await media.visibilityChanged(false);
    expect(engine.playing, isTrue);
    expect(engine.opens, 1);
    expect(engine.position, const Duration(seconds: 25));
    expect(engine.volume, .7);
    await media.seek(const Duration(seconds: -2));
    expect(engine.position, Duration.zero);
    await media.seek(const Duration(days: 1));
    expect(engine.position, engine.duration);
    await media.close();
    expect(engine.closed, isTrue);
  });
  test(
    'audio focus refusal never starts playback and rapid opens select latest',
    () async {
      final engine = FakeMediaEngine();
      final media = MediaSessionController(engine, activate: () async => false);
      await Future.wait([
        media.open('test://old', 'Old'),
        media.open('test://new', 'New'),
      ]);
      expect(media.selectedTitle, 'New');
      expect(engine.opens, 1);
      await media.play();
      expect(engine.playing, isFalse);
      await media.close();
    },
  );
}
