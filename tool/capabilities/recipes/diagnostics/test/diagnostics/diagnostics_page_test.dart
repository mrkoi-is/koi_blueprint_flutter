import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/presentation/providers/diagnostic_providers.dart';
import 'package:__APP_PACKAGE__/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('filters, refreshes and exports one fixed diagnostic revision', (
    tester,
  ) async {
    final store = BoundedDiagnosticStore();
    addTearDown(store.close);
    store.record(AppLogLevel.info, 'needle-alpha', source: 'engine');
    store.record(AppLogLevel.warning, 'needle-beta', source: 'other');
    store.record(
      AppLogLevel.warning,
      'needle-gamma',
      source: 'engine',
      error: StateError('detail'),
    );
    String? exported;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diagnosticStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DiagnosticsPage(
            exporter: (snapshot) async {
              final bytes = await snapshot.fold<List<int>>(
                <int>[],
                (all, chunk) => all..addAll(chunk),
              );
              exported = utf8.decode(bytes);
              return 'diagnostics-export.json';
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('needle-gamma'), findsOneWidget);
    store.record(AppLogLevel.error, 'late-record', source: 'engine');
    await tester.pump();
    expect(find.text('late-record'), findsNothing);
    await tester.tap(find.text('Refresh new records'));
    await tester.pump();
    expect(find.text('late-record'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.enterText(find.byType(TextField).last, 'engine');
    await tester.pump();
    expect(find.text('needle-beta'), findsNothing);
    await tester.tap(find.text('All levels'));
    await tester.pump();
    await tester.tap(find.text('warning').last);
    await tester.pump();
    expect(find.text('needle-gamma'), findsOneWidget);
    expect(find.text('needle-alpha'), findsNothing);

    await tester.tap(find.text('needle-gamma'));
    await tester.pump();
    expect(find.textContaining('detail'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.tap(find.text('Export filtered'));
    await tester.pump();
    expect(exported, contains('needle-gamma'));
    expect(exported, isNot(contains('needle-beta')));
    expect(find.text('diagnostics-export.json'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads older records without replacing the current page', (
    tester,
  ) async {
    final store = BoundedDiagnosticStore();
    addTearDown(store.close);
    for (var i = 0; i < 102; i++) {
      store.record(AppLogLevel.info, 'page-$i');
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [diagnosticStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DiagnosticsPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('page-101'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -10000));
    await tester.pump();
    expect(find.text('Load older records'), findsOneWidget);
    await tester.tap(find.text('Load older records'));
    await tester.pump();
    expect(find.text('page-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'default export reports missing port then retries installed host port',
    (tester) async {
      final store = BoundedDiagnosticStore();
      addTearDown(store.close);
      store.record(AppLogLevel.info, 'host-port-event');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [diagnosticStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DiagnosticsPage(),
          ),
        ),
      );
      await tester.tap(find.text('Export all'));
      await tester.pump();
      expect(
        find.textContaining('Diagnostic export is not installed'),
        findsOneWidget,
      );
      String? exported;
      final release = AppDiagnostics.instance.registerExporter((
        snapshot,
      ) async {
        exported = utf8.decode(
          await snapshot.expand((chunk) => chunk).toList(),
        );
        return 'host-export.json';
      });
      addTearDown(release);
      await tester.tap(find.text('Export all'));
      await tester.pump();
      expect(exported, contains('host-port-event'));
      expect(find.text('host-export.json'), findsOneWidget);
      expect(
        find.textContaining('Diagnostic export is not installed'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
