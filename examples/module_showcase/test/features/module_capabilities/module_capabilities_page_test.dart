import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';
import 'package:module_showcase/features/module_capabilities/presentation/providers/analysis_providers.dart';
import 'package:module_showcase/features/module_capabilities/presentation/screens/module_capabilities_page.dart';
import 'package:module_showcase/l10n/generated/app_localizations.dart';

Future<void> settleResources(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> openPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: buildModuleCapabilitiesPage),
    ),
  );
  await settleResources(tester);
}

AnalysisSession session(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TextField)))
        .read(analysisSessionProvider);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await settleResources(tester);
}

void main() {
  testWidgets(
    'embedded page executes both typed engines and releases on removal',
    (tester) async {
      await openPage(tester);
      final owner = session(tester);
      final first = owner.runtime.state.session!.capability;
      expect(find.textContaining('text.analyze.words'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '鲤 fish 🐟');
      await tapText(tester, 'Run current engine');
      expect(find.text('Word engine: 3'), findsOneWidget);
      await tapText(tester, 'Character engine');
      expect(owner.runtime.state.session?.moduleId, 'characters');
      expect(owner.closedEngines, 1);
      await tapText(tester, 'Run current engine');
      expect(find.text('Character engine: 8'), findsOneWidget);
      expect(find.text('Closed instances: 1'), findsOneWidget);
      await expectLater(
        first.analyze('stale'),
        throwsA(isA<StaleModuleSessionException>()),
      );
      await tester.pumpWidget(const SizedBox());
      await settleResources(tester);
      expect(owner.closedEngines, 2);
      await expectLater(owner.activate('words'), throwsStateError);
      expect(await CapabilityLifecycle.instance.prepare(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration denial and failed initialization are visible and retryable',
    (tester) async {
      await openPage(tester);
      final owner = session(tester);
      await tester.enterText(find.byType(TextField), 'keep this input');
      await tapText(tester, 'Character engine');
      await tapText(tester, 'Enable character engine');
      expect(owner.runtime.state.session, isNull);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.textContaining('Character engine is disabled'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Run current engine'),
            )
            .onPressed,
        isNull,
      );
      await tapText(tester, 'Enable character engine');
      await tapText(tester, 'Fail the next initialization');
      await tapText(tester, 'Character engine');
      expect(
        find.textContaining('Injected engine initialization failure'),
        findsOneWidget,
      );
      expect(owner.failNextCreation, isFalse);
      await tapText(tester, 'Character engine');
      expect(find.text('Available'), findsOneWidget);
      expect(
        find.textContaining('Injected engine initialization failure'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep this input',
      );
      await tapText(tester, 'Run current engine');
      expect(find.text('Character engine: 15'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settleResources(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'host prepare borrows the live engine and host close releases it',
    (tester) async {
      await openPage(tester);
      final owner = session(tester);
      final engine = owner.runtime.state.session!.capability;
      expect(await CapabilityLifecycle.instance.prepare(), isTrue);
      expect((await engine.analyze('still alive')).count, 2);
      await tester.runAsync(CapabilityLifecycle.instance.close);
      expect(owner.closedEngines, 1);
      await expectLater(
        engine.analyze('closed'),
        throwsA(isA<StaleModuleSessionException>()),
      );
      await tester.pumpWidget(const SizedBox());
      await settleResources(tester);
      expect(owner.closedEngines, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
