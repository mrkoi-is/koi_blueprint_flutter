import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  test(
    'locale policy handles scripts, regions and unsupported preferences',
    () {
      final supported = KoiUiLocalizations.supportedLocales;
      expect(
        resolveKoiLocale([const Locale('en', 'GB')], supported),
        const Locale('en'),
      );
      for (final locale in [
        const Locale('zh', 'TW'),
        const Locale('zh', 'HK'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        expect(resolveKoiLocale([locale], supported).scriptCode, 'Hant');
      }
      expect(
        resolveKoiLocale([const Locale('zh', 'CN')], supported),
        const Locale('zh'),
      );
      expect(
        resolveKoiLocale([const Locale('fr'), const Locale('en')], supported),
        const Locale('en'),
      );
      expect(
        resolveKoiLocale([const Locale('fr')], supported),
        const Locale('zh'),
      );
      expect(resolveKoiLocale(null, const []), const Locale('zh'));
      expect(resolveKoiLocale(null, const [Locale('en')]), const Locale('en'));
    },
  );

  testWidgets('host delegate and explicit labels own component wording', (
    tester,
  ) async {
    Widget host(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: KoiUiLocalizations.supportedLocales,
      localizationsDelegates: KoiUiLocalizations.localizationsDelegates,
      home: const Scaffold(
        body: Column(
          children: [
            KoiLoadingState(),
            KoiLoadingState(message: 'Host wording'),
          ],
        ),
      ),
    );
    await tester.pumpWidget(host(const Locale('en')));
    await tester.pump();
    expect(find.text('Preparing workspace…'), findsOneWidget);
    expect(find.text('Host wording'), findsOneWidget);
    await tester.pumpWidget(
      host(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
    );
    await tester.pump();
    expect(find.text('正在準備工作區…'), findsOneWidget);
  });

  test('accent never changes neutral surfaces or error semantics', () {
    for (final brightness in Brightness.values) {
      final baseline = AppTheme.build(brightness: brightness);
      for (final accent in KoiAccent.values) {
        final theme = AppTheme.build(brightness: brightness, accent: accent);
        expect(
          theme.extension<KoiThemeTokens>()!.chromeBackground,
          baseline.extension<KoiThemeTokens>()!.chromeBackground,
        );
        expect(theme.colorScheme.error, baseline.colorScheme.error);
        final a = theme.colorScheme.primary.computeLuminance();
        final b = theme.colorScheme.onPrimary.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('local narrow region uses a modal menu and executes once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KoiMenuLayout(
            width: 320,
            child: KoiMenu(
              items: [
                KoiMenuItem(
                  label: 'Checked',
                  checked: true,
                  onSelected: () => calls++,
                ),
                KoiMenuItem(
                  label: 'Disabled',
                  enabled: false,
                  onSelected: () => calls++,
                ),
              ],
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    final disabled = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Disabled'),
    );
    expect(disabled.onTap, isNull);
    await tester.tap(find.text('Checked'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(BottomSheet), findsNothing);
    final trigger = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Open'),
    );
    expect(trigger.focusNode!.hasFocus, isTrue);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(calls, 1);
  });

  testWidgets('sheet honors Back and large text with keyboard insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 200),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: KoiMenu(
            items: [
              for (var i = 0; i < 15; i++)
                KoiMenuItem(label: 'A long menu item $i', onSelected: () {}),
            ],
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
  testWidgets('removing the trigger dismisses only its owned sheet', (
    tester,
  ) async {
    late StateSetter update;
    var visible = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return visible
                  ? KoiMenu(
                      presentation: KoiMenuPresentation.sheet,
                      items: [KoiMenuItem(label: 'Action', onSelected: () {})],
                      child: const Text('Open'),
                    )
                  : const Text('Remaining page');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Remaining page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
