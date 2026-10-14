import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_lab/main.dart';

Future<void> _openCatalog(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const KoiUiLabApp());
  await tester.tap(find.text('标准组件'));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  final tab = find.widgetWithText(Tab, label);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('button hierarchy and menus execute distinct actions', (
    tester,
  ) async {
    await _openCatalog(tester);
    for (final label in ['主要操作', '次要操作', '边框操作', '辅助操作']) {
      await _tap(tester, find.text(label));
      expect(find.text('$label已执行'), findsOneWidget);
    }
    await _tap(tester, find.text('暂不可用'));
    expect(find.text('辅助操作已执行'), findsOneWidget);
    await _tap(tester, find.byTooltip('刷新目录'));
    expect(find.text('目录已刷新'), findsOneWidget);
    await _tap(tester, find.text('资料菜单'));
    await _tap(tester, find.text('无权限的操作'));
    expect(find.text('目录已刷新'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    await _tap(tester, find.text('复制链接'));
    expect(find.text('已选择复制链接'), findsOneWidget);
    await _tap(tester, find.text('资料菜单'));
    await _tap(tester, find.text('归档资料'));
    expect(find.text('已选择归档资料'), findsOneWidget);
    await _tap(tester, find.text('资料菜单'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('复制链接'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '资料菜单'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    for (final label in ['下载副本', '查看活动']) {
      await _tap(tester, find.byTooltip('更多操作'));
      await _tap(tester, find.text(label));
      expect(find.text('已选择$label'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'validation, dropdown and unsaved inputs survive theme and tabs',
    (tester) async {
      await _openCatalog(tester);
      await _tab(tester, '输入');
      await _tap(tester, find.text('保存成员'));
      expect(find.text('请输入成员姓名'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('catalog-name')),
        '  中文成员  ',
      );
      final role = find.byKey(const ValueKey('catalog-role'));
      await _tap(
        tester,
        find.descendant(of: role, matching: find.byType(IconButton)).last,
      );
      await _tap(tester, find.text('管理员').last);
      await _tap(tester, find.text('保存成员'));
      expect(find.text('已保存 中文成员 · 管理员'), findsOneWidget);
      expect(find.text('请输入成员姓名'), findsNothing);
      await _tap(tester, find.text('暗色主题'));
      await _tab(tester, '操作');
      await _tab(tester, '输入');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('catalog-name')))
            .controller!
            .text,
        '  中文成员  ',
      );
      await _tap(tester, find.text('工作区演示'));
      await _tap(tester, find.text('标准组件'));
      expect(find.text('管理员'), findsOneWidget);
      final search = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(search);
      await tester.enterText(search, '菜单');
      await tester.pumpAndSettle();
      expect(find.text('正在搜索：菜单'), findsOneWidget);
      await _tap(tester, find.byTooltip('清空搜索'));
      expect(find.text('已清空搜索'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection, navigation and table sorting preserve user choices', (
    tester,
  ) async {
    await _openCatalog(tester);
    await _tab(tester, '选择');
    await _tap(tester, find.text('接收更新通知'));
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '接收更新通知'))
          .value,
      isFalse,
    );
    await _tap(tester, find.text('允许成员发表评论'));
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await _tap(tester, find.text('每日摘要'));
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      '摘要',
    );
    await _tap(tester, find.widgetWithText(FilterChip, '图片'));
    await _tap(tester, find.text('网格'));
    expect(find.text('显示：资料、图片 · 网格'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilterChip, '资料'));
    await _tap(tester, find.widgetWithText(FilterChip, '图片'));
    expect(find.text('显示：无 · 网格'), findsOneWidget);
    await _tab(tester, '导航');
    await _tap(tester, find.text('任务'));
    expect(find.text('任务页面：需要处理的待办事项'), findsOneWidget);
    await _tab(tester, '数据');
    await _tap(tester, find.text('交互规范.md'));
    expect(find.text('已选择 1 项资料'), findsOneWidget);
    await _tap(tester, find.text('资料名称'));
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).sortAscending,
      isFalse,
    );
    expect(find.text('已选择 1 项资料'), findsOneWidget);
    await _tap(tester, find.text('交互规范.md'));
    expect(find.text('已选择 0 项资料'), findsOneWidget);
    final selectAll = find
        .descendant(of: find.byType(DataTable), matching: find.byType(Checkbox))
        .first;
    await _tap(tester, selectAll);
    expect(find.text('已选择 3 项资料'), findsOneWidget);
    await _tap(tester, selectAll);
    expect(find.text('已选择 0 项资料'), findsOneWidget);
    await _tab(tester, '导航');
    expect(find.text('任务页面：需要处理的待办事项'), findsOneWidget);
    await _tap(tester, find.text('资料'));
    expect(find.text('资料页面：最近更新的工作区文件'), findsOneWidget);
    await _tab(tester, '选择');
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '接收更新通知'))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      '摘要',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slider updates both determinate progress previews', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openCatalog(tester);
    await _tab(tester, '选择');
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final before = tester.widget<Slider>(slider).value;
    await tester.drag(slider, const Offset(160, 0));
    await tester.pumpAndSettle();
    final after = tester.widget<Slider>(slider).value;
    expect(after, greaterThan(before));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      after,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      after,
    );
    expect(find.text('当前预览：${(after * 100).round()}%'), findsOneWidget);
    expect(find.bySemanticsLabel('预览进度'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('dialog cancel does not commit, validation and confirm do', (
    tester,
  ) async {
    await _openCatalog(tester);
    await _tab(tester, '反馈');
    await _tap(tester, find.text('重命名工作区'));
    await tester.enterText(
      find.byKey(const ValueKey('catalog-rename')),
      '取消的名称',
    );
    await _tap(tester, find.text('取消重命名'));
    expect(find.textContaining('当前工作区：产品设计'), findsOneWidget);
    await _tap(tester, find.text('重命名工作区'));
    await tester.enterText(find.byKey(const ValueKey('catalog-rename')), '   ');
    await _tap(tester, find.text('确认重命名'));
    expect(find.text('名称不能为空'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('catalog-rename')),
      '企业组件工作区',
    );
    await _tap(tester, find.text('确认重命名'));
    expect(find.text('工作区已重命名为 企业组件工作区'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await _tap(tester, find.text('重命名工作区'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('当前工作区：企业组件工作区'), findsOneWidget);
  });

  testWidgets('feedback supports undo, banner actions and sheet cancellation', (
    tester,
  ) async {
    await _openCatalog(tester);
    await _tab(tester, '反馈');
    await _tap(tester, find.text('显示短消息'));
    expect(find.text('资料已移至归档'), findsOneWidget);
    await _tap(tester, find.text('撤销'));
    expect(find.text('已撤销归档'), findsOneWidget);
    await _tap(tester, find.text('显示横幅'));
    await _tap(tester, find.text('稍后'));
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('稍后查看资料更新'), findsOneWidget);
    await _tap(tester, find.text('显示横幅'));
    await _tap(tester, find.text('查看更新'));
    expect(find.text('正在查看资料更新'), findsOneWidget);
    await _tap(tester, find.text('选择排序'));
    await _tap(tester, find.text('取消排序'));
    expect(find.textContaining('排序：最近更新'), findsOneWidget);
    await _tap(tester, find.text('选择排序'));
    await _tap(tester, find.text('名称顺序'));
    expect(find.text('排序已切换为 名称顺序'), findsOneWidget);
    expect(find.textContaining('排序：名称顺序'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard stays in active catalog and narrow overlays remain usable',
    (tester) async {
      await _openCatalog(tester);
      await _tap(tester, find.text('资料菜单'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final hiddenEditors = tester
          .widgetList<EditableText>(
            find.byType(EditableText, skipOffstage: false),
          )
          .toList();
      for (var index = 0; index < 14; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          hiddenEditors.any((editor) => editor.focusNode.hasFocus),
          isFalse,
        );
      }
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('200% 字号'));
      await _tab(tester, '输入');
      final role = find.byKey(const ValueKey('catalog-role'));
      await _tap(
        tester,
        find.descendant(of: role, matching: find.byType(IconButton)).last,
      );
      await _tap(tester, find.text('访客').last);
      expect(tester.takeException(), isNull);
      await _tab(tester, '反馈');
      await _tap(tester, find.text('重命名工作区'));
      await tester.enterText(
        find.byKey(const ValueKey('catalog-rename')),
        '窄窗口',
      );
      await _tap(tester, find.text('确认重命名'));
      expect(find.text('工作区已重命名为 窄窗口'), findsOneWidget);
      await _tap(tester, find.text('选择排序'));
      await _tap(tester, find.text('最早创建'));
      expect(find.text('排序已切换为 最早创建'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320, 600, 1024, 1440]) {
    testWidgets('$width wide at 200% retains usable categories and feedback', (
      tester,
    ) async {
      await _openCatalog(tester);
      await _tap(tester, find.byType(DropdownButton<double>));
      await _tap(tester, find.text('$width px').last);
      await _tap(tester, find.text('紧凑密度'));
      await _tap(tester, find.text('200% 字号'));
      await _tap(tester, find.text('长中文'));
      for (final label in ['操作', '输入', '选择', '导航', '数据', '反馈']) {
        await _tab(tester, label);
        expect(tester.takeException(), isNull, reason: '$width / $label');
      }
      await _tap(tester, find.text('显示横幅'));
      expect(find.text('工作区有新的资料版本，当前编辑内容会保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('稍后'));
      await _tap(tester, find.text('重命名工作区'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('取消重命名'));
      await _tab(tester, '数据');
      final before = tester.getTopLeft(find.text('状态'));
      await tester.drag(
        find.byKey(const ValueKey('catalog-table-scroll')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      if (width == 320) {
        expect(tester.getTopLeft(find.text('状态')).dx, lessThan(before.dx));
      }
      await _tap(tester, find.text('暗色主题'));
      await _tap(tester, find.text('RTL 布局'));
      expect(tester.takeException(), isNull);
    });
  }
}
