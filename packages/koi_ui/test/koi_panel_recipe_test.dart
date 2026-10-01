import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final density in KoiDensity.values) {
      testWidgets(
        '$brightness $density feedback stays reachable at 200 percent',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 300));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var retries = 0;
          Widget host(Widget child) => MaterialApp(
            theme: AppTheme.build(brightness: brightness, density: density),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: child),
          );
          await tester.pumpWidget(
            host(
              KoiErrorState(
                title: '工作区初始化失败',
                description: '无法读取当前工作区中的中文资料。请检查存储状态，然后重试。',
                onRetry: () => retries++,
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('重试'));
          await tester.tap(find.text('重试'));
          expect(retries, 1);
          await tester.pumpWidget(
            host(
              const KoiEmptyState(
                title: '暂无匹配的中文资料',
                description: '试试清除搜索条件，或者导入新的工作区资料。',
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            host(const KoiLoadingState(message: '正在恢复当前工作区中的中文资料，请稍候…')),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'search clears once, restores input focus and follows external values',
    (tester) async {
      var clears = 0;
      final controller = TextEditingController(text: '中文资料');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: KoiSearchField(
              hintText: '搜索',
              controller: controller,
              onChanged: (value) {
                if (value.isEmpty) clears++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      expect(clears, 1);
      expect(controller.text, '');
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      controller.text = '媒体';
      await tester.pump();
      expect(find.text('媒体'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.text = '宿主仍拥有控制器';
      controller.dispose();
    },
  );
  testWidgets(
    'search initial value updates and controller ownership switches safely',
    (tester) async {
      final external = TextEditingController(text: '外部');
      Widget host({String? value, TextEditingController? controller}) =>
          MaterialApp(
            home: Scaffold(
              body: KoiSearchField(
                hintText: '搜索',
                initialValue: value,
                controller: controller,
              ),
            ),
          );
      await tester.pumpWidget(host(value: '旧查询'));
      await tester.pumpWidget(host(value: '新查询'));
      expect(find.text('新查询'), findsOneWidget);
      await tester.pumpWidget(host(controller: external));
      expect(find.text('外部'), findsOneWidget);
      await tester.pumpWidget(host(value: '恢复内部'));
      expect(find.text('恢复内部'), findsOneWidget);
      external.text = '未被组件销毁';
      external.dispose();
    },
  );
  testWidgets('panel heading stays fixed while its body scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 300,
            child: KoiPanel(
              title: '资料标题',
              search: const KoiSearchField(hintText: '搜索'),
              child: ListView(
                children: [
                  for (var i = 0; i < 100; i++) ListTile(title: Text('资料 $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.text('资料标题'));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('资料标题')), origin);
    expect(tester.takeException(), isNull);
  });
  testWidgets('clear affordance does not change compact search height', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(density: KoiDensity.compact),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: KoiSearchField(hintText: '搜索', controller: controller),
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byType(KoiSearchField)).height;
    controller.text = '中文';
    await tester.pump();
    expect(tester.getSize(find.byType(KoiSearchField)).height, before);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
