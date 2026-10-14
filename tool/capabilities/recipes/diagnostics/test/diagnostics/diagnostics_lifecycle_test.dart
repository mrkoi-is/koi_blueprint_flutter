import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/data/persistent_diagnostics.dart';

void main() {
  test(
    'concurrent install shares IO and its disposer preserves a newer exporter',
    () async {
      addTearDown(disposePersistentDiagnostics);
      final ready = Completer<BoundedDiagnosticStore>();
      var opens = 0;
      Future<BoundedDiagnosticStore> open() {
        opens++;
        return ready.future;
      }

      final first = initializePersistentDiagnostics(
        openStore: open,
        exporter: (_) async => 'first.json',
      );
      final second = initializePersistentDiagnostics(
        openStore: open,
        exporter: (_) async => 'second.json',
      );
      expect(opens, 1);
      ready.complete(BoundedDiagnosticStore());
      await Future.wait([first, second]);
      await initializePersistentDiagnostics(openStore: open);
      expect(opens, 1);
      expect(
        await AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
        'first.json',
      );
      final releaseNew = AppDiagnostics.instance.registerExporter(
        (_) async => 'new-owner.json',
      );
      addTearDown(releaseNew);
      await disposePersistentDiagnostics();
      await disposePersistentDiagnostics();
      expect(
        await AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
        'new-owner.json',
      );
    },
  );

  test(
    'failed initialization leaves no port and a later retry can install it',
    () async {
      addTearDown(disposePersistentDiagnostics);
      await expectLater(
        initializePersistentDiagnostics(
          openStore: () async => throw StateError('open failed'),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
        throwsA(isA<UnsupportedError>()),
      );
      await initializePersistentDiagnostics(
        openStore: () async => BoundedDiagnosticStore(),
        exporter: (_) async => 'retry.json',
      );
      expect(
        await AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
        'retry.json',
      );
      await disposePersistentDiagnostics();
      await expectLater(
        AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
  test('disposal during initialization waits and leaves no exporter', () async {
    addTearDown(disposePersistentDiagnostics);
    final ready = Completer<BoundedDiagnosticStore>();
    final opening = initializePersistentDiagnostics(
      openStore: () => ready.future,
      exporter: (_) async => 'must-be-removed.json',
    );
    var disposed = false;
    final closing = disposePersistentDiagnostics().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    ready.complete(BoundedDiagnosticStore());
    await Future.wait([opening, closing]);
    expect(disposed, isTrue);
    await expectLater(
      AppDiagnostics.instance.exportSnapshot(const Stream.empty()),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
