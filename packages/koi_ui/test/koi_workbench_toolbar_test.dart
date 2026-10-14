import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

Widget _host(
  KoiWorkbenchController controller, {
  bool header = false,
  bool detail = true,
  double inset = 0,
  TextEditingController? editor,
}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: EdgeInsets.only(bottom: inset),
      viewPadding: EdgeInsets.only(bottom: inset),
      textScaler: TextScaler.linear(2),
    ),
    child: child!,
  ),
  home: KoiWorkbenchFrame(
    controller: controller,
    showHeader: header,
    title: const Text('工作区'),
    headerLeading: header ? const KoiNavigationHistoryControls() : null,
    destinations: const [
      KoiNavigationDestination(
        id: 'text',
        label: '文本',
        icon: Icons.description,
      ),
      KoiNavigationDestination(id: 'tasks', label: '任务', icon: Icons.task_alt),
    ],
    selectedId: 'text',
    onDestinationSelected: (_) {},
    sidebar: const Text('资料列表'),
    detail: detail ? const Text('资料属性') : null,
    navigationTrailing: IconButton(
      tooltip: '设置',
      onPressed: () {},
      icon: const Icon(Icons.settings_outlined),
    ),
    body: editor == null ? const Text('当前内容') : TextField(controller: editor),
  ),
);

void main() {
  for (final count in [1, 2, 3]) {
    for (final header in [false, true]) {
      for (final width in [320.0, 600.0, 1024.0]) {
        testWidgets(
          'settings reachable: $count destinations, header=$header, width=$width',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 700));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            var activations = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light,
                home: KoiWorkbenchFrame(
                  showHeader: header,
                  title: const Text('工作区'),
                  destinations: List.generate(
                    count,
                    (i) => KoiNavigationDestination(
                      id: '$i',
                      label: '页面$i',
                      icon: Icons.description_outlined,
                    ),
                  ),
                  selectedId: '0',
                  onDestinationSelected: (_) {},
                  navigationTrailing: IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => activations++,
                  ),
                  body: const Text('内容'),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byTooltip('设置'), findsOneWidget);
            await tester.tap(find.byTooltip('设置'));
            expect(activations, 1);
            if (count == 1) expect(find.byType(NavigationBar), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('host panel commands at $width need no second bar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = KoiWorkbenchController();
      final editor = TextEditingController(text: '保留中文草稿');
      await tester.pumpWidget(_host(controller, editor: editor));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('设置'), findsOneWidget);
      expect(controller.canToggleSidebar, isTrue);
      expect(controller.canToggleDetail, isTrue);
      if (width >= 1024) {
        controller.toggleSidebar();
        controller.toggleDetail();
        await tester.pumpAndSettle();
        expect(find.text('资料列表'), findsNothing);
        expect(find.text('资料属性'), findsNothing);
        expect(controller.sidebarOpen, isFalse);
        expect(controller.detailOpen, isFalse);
      } else {
        controller.toggleSidebar();
        await tester.pumpAndSettle();
        expect(find.text('资料列表'), findsOneWidget);
        expect(controller.sidebarOpen, isTrue);
        controller.toggleSidebar();
        await tester.pumpAndSettle();
        expect(controller.sidebarOpen, isFalse);
        controller.toggleDetail();
        await tester.pumpAndSettle();
        expect(find.text('资料属性'), findsOneWidget);
        expect(controller.detailOpen, isTrue);
        controller.toggleDetail();
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(editor),
      );
      expect(editor.text, '保留中文草稿');
      await tester.pumpWidget(_host(controller, detail: false, editor: editor));
      await tester.pumpAndSettle();
      expect(controller.canToggleDetail, isFalse);
      controller.toggleDetail();
      await tester.pumpAndSettle();
      expect(find.text('资料属性'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      editor.dispose();
    });
  }

  testWidgets('Material bottom bar adds the safe inset only once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KoiWorkbenchController();
    await tester.pumpWidget(_host(controller, inset: 34));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NavigationBar)).height, 114);
    expect(tester.getRect(find.byType(NavigationBar)).bottom, 800);
    expect(
      tester.getRect(find.byTooltip('设置')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('Flutter fallback has panel icons in one compact header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KoiWorkbenchController();
    await tester.pumpWidget(_host(controller, header: true));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
    expect(find.byType(KoiPanelIcon), findsNWidgets(2));
    expect(find.byIcon(Icons.info_outline), findsNothing);
    await tester.tap(find.byTooltip('切换详情面板'));
    await tester.pumpAndSettle();
    expect(find.text('资料属性'), findsOneWidget);
    controller.toggleDetail();
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(controller, header: true, detail: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换详情面板'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
