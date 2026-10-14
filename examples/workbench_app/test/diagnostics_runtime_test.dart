import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:workbench_app/core/diagnostics/app_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one host install captures duplicate pathways once and restores handlers',
    () async {
      final oldHandler = FlutterError.onError;
      final oldSink = AppLogger.sink;
      var forwarded = 0;
      void previous(FlutterErrorDetails _) {
        forwarded++;
      }

      FlutterError.onError = previous;
      final runtime = AppDiagnostics();
      addTearDown(() {
        FlutterError.onError = oldHandler;
        AppLogger.sink = oldSink;
      });
      runtime.install();
      final installed = FlutterError.onError;
      runtime.install();
      expect(identical(installed, FlutterError.onError), isTrue);
      final error = StateError('same failure');
      runtime.record(error, StackTrace.current, 'provider');
      FlutterError.onError!(FlutterErrorDetails(exception: error));
      expect(runtime.store.query(const DiagnosticQuery()).items, hasLength(1));
      expect(forwarded, 1);
      await Future<void>.delayed(Duration.zero);
      runtime.record(error, StackTrace.current, 'provider');
      expect(runtime.store.query(const DiagnosticQuery()).items, hasLength(2));
      await runtime.close();
      expect(identical(FlutterError.onError, previous), isTrue);
      expect(identical(AppLogger.sink, oldSink), isTrue);
    },
  );
  test('closing does not overwrite another host handler and replacement preserves logs', () async {
    final oldHandler = FlutterError.onError;
    final oldSink = AppLogger.sink;
    final runtime = AppDiagnostics();
    addTearDown(() {
      FlutterError.onError = oldHandler;
      AppLogger.sink = oldSink;
    });
    runtime.install();
    runtime.store.record(AppLogLevel.info, 'startup');
    final replacement = BoundedDiagnosticStore();
    await runtime.replaceStore(replacement);
    expect(
      replacement.query(const DiagnosticQuery()).items.single.message,
      'startup',
    );
    void other(FlutterErrorDetails _) {}
    FlutterError.onError = other;
    await runtime.close();
    expect(identical(FlutterError.onError, other), isTrue);
  });
  test(
    'export port is explicit and stale disposal preserves its successor',
    () async {
      final runtime = AppDiagnostics();
      addTearDown(runtime.close);
      await expectLater(
        runtime.exportSnapshot(const Stream<List<int>>.empty()),
        throwsA(isA<UnsupportedError>()),
      );
      var calls = 0;
      Future<String> exporter(Stream<List<int>> snapshot) async {
        calls++;
        final bytes = await snapshot.expand((chunk) => chunk).toList();
        expect(bytes, [1, 2, 3]);
        return 'export.json';
      }

      final stale = runtime.registerExporter(exporter);
      final current = runtime.registerExporter(exporter);
      stale();
      expect(
        await runtime.exportSnapshot(Stream.value([1, 2, 3])),
        'export.json',
      );
      expect(calls, 1);
      current();
      current();
      await expectLater(
        runtime.exportSnapshot(const Stream<List<int>>.empty()),
        throwsA(isA<UnsupportedError>()),
      );
      runtime.registerExporter((_) => Future.error(StateError('disk-full')));
      await expectLater(
        runtime.exportSnapshot(const Stream<List<int>>.empty()),
        throwsA(isA<StateError>()),
      );
      await runtime.close();
      await expectLater(
        runtime.exportSnapshot(const Stream<List<int>>.empty()),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
