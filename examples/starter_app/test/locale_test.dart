import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starter_app/app.dart';
import 'package:starter_app/core/preferences/appearance_providers.dart';
import 'package:starter_app/core/preferences/ui_preferences_store.dart';
import 'package:starter_app/features/home/presentation/screens/home_page.dart';
import 'package:starter_app/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'system language, explicit choice and reset preserve the router',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('zh', 'TW')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final store = MemoryUiPreferencesStore();
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      const traditional = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      );
      Locale renderedLocale() =>
          Localizations.localeOf(tester.element(find.byType(HomePage)));
      expect(renderedLocale(), traditional);
      expect(
        find.text(lookupAppLocalizations(traditional).ready),
        findsOneWidget,
      );
      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig;
      final notifier = container.read(appAppearanceProvider.notifier);
      notifier.setLocale(const Locale('en'));
      await tester.pumpAndSettle();
      expect(renderedLocale(), const Locale('en'));
      tester.platformDispatcher.localesTestValue = [const Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      expect(renderedLocale(), const Locale('en'));
      expect(await notifier.flush(), isTrue);
      expect((await store.read())['locale'], 'en');
      notifier.setLocale(null);
      await tester.pumpAndSettle();
      expect(renderedLocale(), const Locale('zh'));
      expect(await notifier.flush(), isTrue);
      expect((await store.read())['locale'], isNull);
      tester.platformDispatcher.localesTestValue = [
        const Locale('fr'),
        const Locale('en', 'GB'),
      ];
      await tester.pumpAndSettle();
      expect(renderedLocale(), const Locale('en'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig,
        same(router),
      );
      expect((await store.read())['locale'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final tag in ['zh_Hant', 'removed-language']) {
    testWidgets('restores $tag against the available ARB locales', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final store = MemoryUiPreferencesStore();
      await store.write({'locale': tag});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      final locale = Localizations.localeOf(
        tester.element(find.byType(HomePage)),
      );
      expect(
        locale,
        tag == 'zh_Hant'
            ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
            : const Locale('zh'),
      );
      expect(find.text(lookupAppLocalizations(locale).ready), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
