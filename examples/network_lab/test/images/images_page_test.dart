import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/images/images_capability.dart';

Future<void> settleImages(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pump();
}

String imagePageText() => find
    .byType(Text)
    .evaluate()
    .map((element) {
      final text = element.widget as Text;
      return text.data ?? text.textSpan?.toPlainText() ?? '';
    })
    .join(' | ');

void main() {
  // Browser widget tests have no native UNIT_TEST_ASSETS channel. Supply only
  // the declared sample resource at that boundary; keep the real engine codec.
  setUp(() {
    if (!kIsWeb) return;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAQAAAACgCAYAAADjGbI8AAACAElEQVR4nO3UIQEAIBDAwK9EH8LQHGIgduL81Gbtc4Gm+R0A/GMAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEGYAEPYAHC6TKtJWhlwAAAAASUVORK5CYII=',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          return key == 'assets/images/sample.png'
              ? ByteData.sublistView(bytes)
              : null;
        });
  });
  tearDown(() {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    }
  });
  testWidgets(
    'images follow all host locales while retaining layout and decoded state',
    (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: buildImagesCapabilityPage),
          ),
        ),
      );
      await settleImages(tester);
      await tester.drag(find.byType(Slider), const Offset(-50, 0));
      await settleImages(tester);
      final width = tester.widget<Slider>(find.byType(Slider)).value;
      for (final entry in [
        (const Locale('en'), 'Choose local image', 'Decoded'),
        (const Locale('zh'), '选择本地图片', '实际解码'),
        (
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          '選擇本機圖片',
          '實際解碼',
        ),
      ]) {
        locale.value = entry.$1;
        await settleImages(tester);
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          find.textContaining(entry.$3),
          findsOneWidget,
          reason: imagePageText(),
        );
        expect(tester.widget<Slider>(find.byType(Slider)).value, width);
        expect(find.byType(RawImage), findsOneWidget, reason: imagePageText());
      }
      await tester.pumpWidget(const SizedBox());
      await settleImages(tester);
    },
  );
  testWidgets(
    'installed image page decodes Asset/Memory with DPR resizing and network error retry',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: buildImagesCapabilityPage),
        ),
      );
      await settleImages(tester);
      expect(find.byType(RawImage), findsOneWidget, reason: imagePageText());
      expect(find.textContaining('DPR 2.00'), findsOneWidget);
      expect(find.textContaining('实际解码 256 × 160'), findsOneWidget);
      await tester.tap(find.text('内存图片'));
      await settleImages(tester);
      expect(find.byType(RawImage), findsOneWidget, reason: imagePageText());
      await tester.drag(find.byType(Slider), const Offset(-250, 0));
      await settleImages(tester);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image!.width,
        lessThanOrEqualTo(256),
      );
      await tester.enterText(find.byType(TextField), 'file:///invalid');
      await tester.tap(find.text('网络图片'));
      await settleImages(tester);
      expect(find.textContaining('Image URL must be HTTP(S)'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await settleImages(tester);
      expect(find.textContaining('Image URL must be HTTP(S)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settleImages(tester);
    },
  );
}
