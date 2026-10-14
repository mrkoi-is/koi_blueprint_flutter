import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  test(
    'cancelled preparation leaves live resources available for a retry',
    () async {
      final lifecycle = CapabilityLifecycle();
      var mayExit = false;
      var closed = 0;
      lifecycle.register(
        prepare: () async => mayExit,
        close: () async {
          closed++;
        },
      );
      expect(await lifecycle.prepare(), isFalse);
      expect(closed, 0);
      mayExit = true;
      expect(await lifecycle.prepare(), isTrue);
      expect(closed, 0);
      await lifecycle.close();
      await lifecycle.close();
      expect(closed, 1);
    },
  );
  test('cleanup waits for real work, continues after failure, unregisters departed pages', () async {
    final lifecycle = CapabilityLifecycle();
    final calls = <int>[];
    final gate = Completer<void>();
    lifecycle.register(
      prepare: () async => true,
      close: () async {
        calls.add(1);
      },
    );
    final unregister = lifecycle.register(
      prepare: () async => false,
      close: () async {
        calls.add(2);
      },
    );
    unregister();
    lifecycle.register(
      prepare: () async => true,
      close: () async {
        calls.add(3);
        await gate.future;
        throw StateError('close failed');
      },
    );
    expect(await lifecycle.prepare(), isTrue);
    final closing = lifecycle.close();
    final assertion = expectLater(closing, throwsStateError);
    expect(calls, [3]);
    expect(
      () => lifecycle.register(prepare: () async => true, close: () async {}),
      throwsStateError,
    );
    gate.complete();
    await assertion;
    expect(calls, [3, 1]);
    lifecycle.register(
      prepare: () async => true,
      close: () async {
        calls.add(4);
      },
    );
    await lifecycle.close();
    expect(calls, [3, 1, 4]);
  });
  test('empty close permits the next bootstrap to acquire resources', () async {
    final lifecycle = CapabilityLifecycle();
    await lifecycle.close();
    lifecycle.register(prepare: () async => true, close: () async {});
    await lifecycle.close();
  });
}
