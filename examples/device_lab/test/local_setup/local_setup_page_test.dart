import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:device_lab/features/local_setup/application/local_setup_session.dart';
import 'package:device_lab/features/local_setup/presentation/providers/local_setup_providers.dart';
import 'package:device_lab/features/local_setup/presentation/screens/local_setup_page.dart';
import 'package:device_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets(
    'local page follows provider changes, protects draft, and retries save without losing text',
    (tester) async {
      final store = MemorySettings();
      final session = LocalSetupSession(
        store: store,
        requireOnboarding: false,
        pickDirectory: () async => '/selected',
        pickDocument: (_) async =>
            const ImportedDocument('chosen.txt', 'imported bytes'),
        importFile: (_) async =>
            const ImportedDocument('external.txt', 'external bytes'),
      );
      await session.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localSetupSessionProvider.overrideWithValue(session)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LocalSetupPage(onboarding: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Text'),
        'keep this draft',
      );
      await tester.tap(find.text('Open intent'));
      await tester.pumpAndSettle();
      expect(find.text('Draft protected: 1 pending intents'), findsOneWidget);
      store.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(session.draft, 'keep this draft');
      store.fail = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(session.tab, 'tasks');
      expect(session.incoming.pendingCount, 0);
      await tester.tap(find.text('Import text file'));
      await tester.pumpAndSettle();
      expect(session.draft, 'imported bytes');
      await session.configure(
        const OnboardingState(
          step: OnboardingStep.complete,
          language: 'zh-Hant',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('外部入口'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await session.close();
      expect(store.closed, true);
      expect(tester.takeException(), isNull);
    },
  );
}
