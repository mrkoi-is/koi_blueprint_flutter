import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/media/capture_video_frame.dart';

void main() {
  test('ready frame is returned without another capture', () async {
    final frame = Uint8List.fromList([1, 2, 3]);
    var calls = 0;
    final actual = await captureVideoFrame(() async {
      calls++;
      return frame;
    }, isActive: () => true);
    expect(actual, same(frame));
    expect(calls, 1);
  });

  test('texture registration can precede a readable decoded frame', () async {
    final frame = Uint8List.fromList([1, 2, 3]);
    final frames = <Uint8List?>[null, Uint8List(0), frame];
    var calls = 0;
    final actual = await captureVideoFrame(
      () async => frames[calls++],
      isActive: () => true,
      retryDelay: Duration.zero,
    );
    expect(actual, same(frame));
    expect(calls, 3);
  });

  test('an unreadable stream exhausts its finite capture budget', () async {
    var calls = 0;
    final actual = await captureVideoFrame(
      () async {
        calls++;
        return null;
      },
      isActive: () => true,
      attempts: 3,
      retryDelay: Duration.zero,
    );
    expect(actual, isNull);
    expect(calls, 3);
  });

  test(
    'capture errors remain observable without repeating the operation',
    () async {
      var calls = 0;
      await expectLater(
        captureVideoFrame(() async {
          calls++;
          throw StateError('decoder failed');
        }, isActive: () => true),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test('a closed owner never starts a capture', () async {
    var calls = 0;
    final actual = await captureVideoFrame(() async {
      calls++;
      return Uint8List(1);
    }, isActive: () => false);
    expect(actual, isNull);
    expect(calls, 0);
  });

  for (final lateFrame in <Uint8List?>[
    null,
    Uint8List.fromList([1]),
  ]) {
    test(
      'close during capture discards the result and prevents a retry: $lateFrame',
      () async {
        var active = true;
        var calls = 0;
        final started = Completer<void>();
        final pending = Completer<Uint8List?>();
        final capture = captureVideoFrame(
          () {
            calls++;
            started.complete();
            return pending.future;
          },
          isActive: () => active,
          retryDelay: Duration.zero,
        );
        await started.future;
        active = false;
        pending.complete(lateFrame);
        expect(await capture, isNull);
        expect(calls, 1);
      },
    );
  }
}
