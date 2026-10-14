import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  group('状态组件', () {
    testWidgets('KoiLoadingState 展示进度和消息', (tester) async {
      await tester.pumpWidget(
        _testApp(const KoiLoadingState(message: '正在加载订单...')),
      );

      expect(find.text('正在加载订单...'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is ProgressIndicator),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('KoiEmptyState 展示标题、描述和空状态图标', (tester) async {
      await tester.pumpWidget(
        _testApp(const KoiEmptyState(title: '暂无订单', description: '新订单会显示在这里')),
      );

      expect(find.text('暂无订单'), findsOneWidget);
      expect(find.text('新订单会显示在这里'), findsOneWidget);
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('KoiErrorState 无回调时不展示重试按钮', (tester) async {
      await tester.pumpWidget(
        _testApp(const KoiErrorState(title: '加载失败', description: '请稍后再试')),
      );

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('请稍后再试'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('KoiErrorState 点击重试执行回调', (tester) async {
      var retryCount = 0;
      await tester.pumpWidget(
        _testApp(
          KoiErrorState(
            title: '加载失败',
            description: '请稍后再试',
            onRetry: () => retryCount += 1,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pump();

      expect(retryCount, 1);
    });
  });

  group('AppTheme', () {
    testWidgets('light theme 可渲染状态组件', (tester) async {
      late ThemeData observedTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              observedTheme = Theme.of(context);
              return const Scaffold(body: KoiLoadingState());
            },
          ),
        ),
      );

      expect(observedTheme.brightness, Brightness.light);
      expect(observedTheme.useMaterial3, isTrue);
      expect(observedTheme.colorScheme.primary, AppColors.moss);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme 可渲染状态组件', (tester) async {
      late ThemeData observedTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              observedTheme = Theme.of(context);
              return const Scaffold(
                body: KoiEmptyState(title: '暂无内容', description: '稍后再来看看'),
              );
            },
          ),
        ),
      );

      expect(observedTheme.brightness, Brightness.dark);
      expect(observedTheme.useMaterial3, isTrue);
      expect(observedTheme.scaffoldBackgroundColor, AppColors.night);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}
