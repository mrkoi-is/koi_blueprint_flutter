@TestOn('vm')
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:koi_ui/theme/koi_material_theme.dart';

import 'golden_environment.dart';

void main() {
  final supported = Platform.isMacOS && Abi.current() == Abi.macosArm64;
  late String baselineDirectory;
  setUpAll(() async {
    if (!supported) return;
    final version = await Process.run('/usr/bin/sw_vers', ['-productVersion']);
    if (version.exitCode != 0 || version.stdout is! String) {
      throw StateError('Cannot determine macOS version for Golden tests');
    }
    baselineDirectory = goldenBaselineForMacVersion(version.stdout as String);
    final bytes = await File('test/golden/fonts/KoiGoldenSans.ttf')
        .readAsBytes();
    await (FontLoader(
      'KoiGoldenSans',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });

  for (final scenario in [
    (name: 'error_light', dark: false, large: false, width: 480.0),
    (name: 'error_dark', dark: true, large: false, width: 480.0),
    (name: 'empty_narrow_large', dark: false, large: true, width: 320.0),
  ]) {
    testWidgets(
      'golden ${scenario.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scenario.width, 480);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final theme = AppTheme.build(
          brightness: scenario.dark ? Brightness.dark : Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            // Reapply component styles after the test font: buttons cache their
            // text style in the real theme, not only in ThemeData.textTheme.
            theme: applyKoiMaterialTheme(
              theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'KoiGoldenSans'),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: 'KoiGoldenSans',
                ),
              ),
              theme.extension<KoiThemeTokens>()!,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scenario.large ? 2 : 1),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('golden-status'),
              child: Scaffold(
                body: scenario.large
                    ? const KoiEmptyState(
                        title: '暂无资料',
                        description: '导入资料后可在这里查看与编辑。',
                      )
                    : KoiErrorState(
                        title: '读取失败',
                        description: '网络暂时不可用，请稍后重试。文件与草稿仍然保留。',
                        onRetry: () {},
                      ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('golden-status')),
          matchesGoldenFile('$baselineDirectory/${scenario.name}.png'),
        );
      },
      // Other hosts are NOT_RUN; they cannot validate this baseline.
      skip: !supported,
    );
  }
}
