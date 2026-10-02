import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/core/preferences/appearance_providers.dart';
import 'package:platform_lab/core/preferences/ui_preferences_store.dart';
import 'package:platform_lab/features/settings/presentation/settings_page.dart';
import 'package:platform_lab/l10n/generated/app_localizations.dart';

class _Preferences implements UiPreferencesStore {
  final delegate = MemoryUiPreferencesStore();
  @override
  Future<Map<String, Object?>> read() => delegate.read();
  @override
  Future<void> close() => delegate.close();
  bool fail = false;
  @override
  Future<void> write(Map<String, Object?> values) async {
    if (fail) throw StateError('disk unavailable');
    return delegate.write(values);
  }
}

class _Host extends ConsumerWidget {
  const _Host();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appAppearanceProvider).value;
    return MaterialApp(
      locale: preferences?.locale ?? const Locale('en'),
      localizationsDelegates: [
        KoiUiLocalizations.delegate,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.build(accent: preferences?.accent ?? KoiAccent.moss),
      darkTheme: AppTheme.build(
        brightness: Brightness.dark,
        accent: preferences?.accent ?? KoiAccent.moss,
      ),
      themeMode: preferences?.themeMode ?? ThemeMode.light,
      home: const SettingsPage(),
    );
  }
}

void main() {
  testWidgets('search, immediate host theme, persistence failure and retry', (
    tester,
  ) async {
    final store = _Preferences();
    final container = ProviderContainer(
      overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Host()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Color mode');
    await tester.pumpAndSettle();
    expect(find.text('Display language'), findsNothing);
    expect(
      find
          .text('Color mode', findRichText: false)
          .evaluate()
          .where((element) => element.widget is Text),
      hasLength(1),
    );
    store.fail = true;
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    expect(
      find.text('Settings could not be saved. Retry to persist your choices.'),
      findsOneWidget,
    );
    store.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect((await store.read())['themeMode'], 'dark');
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    'automatic density selection persists without changing the saved manual choice',
    (tester) async {
      final store = MemoryUiPreferencesStore();
      await store.write({'density': 'compact'});
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const _Host()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Interface density');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<KoiDensityMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatic (current input)').last);
      await tester.pumpAndSettle();
      expect((await store.read())['automaticDensity'], isTrue);
      expect((await store.read())['density'], 'compact');
      await tester.tap(find.byType(DropdownButton<KoiDensityMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comfortable').last);
      await tester.pumpAndSettle();
      expect((await store.read())['automaticDensity'], isFalse);
      expect((await store.read())['density'], 'comfortable');
    },
  );

  testWidgets('reset confirms, preserves unrelated keys and fits large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = MemoryUiPreferencesStore();
    await store.write({
      'accent': 'violet',
      'themeMode': 'dark',
      'density': 'compact',
      'futureSetting': 42,
    });
    final container = ProviderContainer(
      overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Host()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'nothing-match');
    await tester.pumpAndSettle();
    expect(find.text('No matching settings'), findsOneWidget);
    await tester.ensureVisible(find.text('Restore defaults'));
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await store.read())['accent'], 'violet');
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore defaults'));
    await tester.pumpAndSettle();
    expect(await store.read(), {
      'locale': null,
      'accent': 'moss',
      'themeMode': 'system',
      'density': 'comfortable',
      'futureSetting': 42,
      'automaticDensity': false,
    });
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'changing language updates the complete host and stores a script-aware locale',
    (tester) async {
      final store = MemoryUiPreferencesStore();
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const _Host()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('繁體中文').last);
      await tester.pumpAndSettle();
      expect(find.text('顯示語言'), findsOneWidget);
      expect(find.text('設定'), findsOneWidget);
      expect((await store.read())['locale'], 'zh-Hant');
    },
  );
}
