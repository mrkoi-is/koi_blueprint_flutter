@TestOn('vm')
library;

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'native_capability_support.dart';

void _slowSignal(SendPort port) async {
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  port.send('ready');
}

void main() {
  testWidgets('waits for real isolate events beyond the old 2 second limit', (
    tester,
  ) async {
    final port = ReceivePort();
    var ready = false;
    final subscription = port.listen((message) => ready = message == 'ready');
    final isolate = (await tester.runAsync(
      () => Isolate.spawn(_slowSignal, port.sendPort),
    ))!;
    addTearDown(() async {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    });
    final watch = Stopwatch()..start();
    await waitForCapability(tester, () => ready);
    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));
  });

  testWidgets('timeout remains a failure and reports caller state', (
    tester,
  ) async {
    await expectLater(
      waitForCapability(
        tester,
        () => false,
        timeout: const Duration(milliseconds: 50),
        describe: () => 'operation=pending',
      ),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.message,
          'message',
          contains('state=operation=pending'),
        ),
      ),
    );
  });

  testWidgets('completed operation errors remain visible', (tester) async {
    await expectLater(
      completeCapability<void>(
        tester,
        () async => throw StateError('original write failure'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'original write failure',
        ),
      ),
    );
  });
}
