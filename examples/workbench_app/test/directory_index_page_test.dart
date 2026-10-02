import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/core/router/app_routes.dart';
import 'package:workbench_app/features/workspace/presentation/screens/directory_index_page.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';
import 'package:workbench_app/features/workspace/domain/directory_selection.dart';
import 'package:workbench_app/features/workspace/presentation/providers/directory_index_providers.dart';
import 'package:workbench_app/l10n/app_strings.dart';

void main() {
  testWidgets(
    'directory page exposes selection, indexed files and incremental rescan',
    (tester) async {
      final picker = _Picker();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [directoryIndexPickerProvider.overrideWithValue(picker)],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const DirectoryIndexPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('目录索引'), findsOneWidget);
      await tester.tap(find.text('选择目录'));
      await finishScan(tester);
      expect(find.text('资料.txt'), findsOneWidget);
      expect(picker.source.reads, 1);
      await tester.tap(find.text('重新扫描'));
      await finishScan(tester);
      expect(picker.source.reads, 1);
      expect(find.textContaining('复用 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('uninstalled capability route explains its availability', (
    tester,
  ) async {
    final router = GoRouter(
      routes: $appRoutes,
      initialLocation: const CapabilityRoute(id: 'not-installed').location,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未安装'), findsOneWidget);
    expect(find.byType(DirectoryIndexPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> finishScan(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DirectoryIndexPage)),
  );
  // StreamIterator.cancel can return an SDK future created outside FakeAsync.
  // Pump both real cleanup and widget frames, with a bounded completion check.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final state = container.read(directoryIndexControllerProvider);
    if (!state.busy && !state.selecting) break;
  }
  final state = container.read(directoryIndexControllerProvider);
  expect(state.busy, isFalse);
  expect(state.selecting, isFalse);
  await tester.pumpAndSettle();
}

final class _Picker implements DirectoryIndexPicker {
  final source = _Source();
  @override
  Future<DirectorySelection?> pick() async =>
      DirectorySelection(label: '选定的目录', identity: 'fixture', source: source);
}

final class _Source implements DirectoryIndexSource {
  int reads = 0;
  @override
  Stream<DirectoryCandidate> enumerate() => Stream.value(
    const DirectoryCandidate(key: 'nested/资料.txt', name: '资料.txt'),
  );
  @override
  Future<DirectoryFingerprint> fingerprint(
    DirectoryCandidate candidate,
  ) async =>
      DirectoryFingerprint(byteLength: 42, modifiedAt: DateTime.utc(2026));
  @override
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  ) async {
    reads++;
    return IndexedFile(
      key: candidate.key,
      name: candidate.name,
      fingerprint: fingerprint,
      fileType: 'txt',
    );
  }
}
