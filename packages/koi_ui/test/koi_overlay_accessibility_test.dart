import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  testWidgets(
    'modal popover hides the background and traps focus until Escape',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('后台操作')),
                  KoiPopover(
                    label: '资料操作',
                    child: const Text('资料操作'),
                    builder: (context, close) => Column(
                      children: [
                        TextButton(
                          focusNode: first,
                          onPressed: () {},
                          child: const Text('首项'),
                        ),
                        TextButton(
                          focusNode: second,
                          onPressed: close,
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final trigger = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '资料操作'),
        );
        // A visible text label and explicit label should not be spoken twice.
        expect(
          tester.getSemantics(find.widgetWithText(TextButton, '资料操作')).label,
          '资料操作',
        );
        await tester.tap(find.text('资料操作'));
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel('后台操作'), findsNothing);
        expect(first.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(second.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(first.hasFocus, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(second.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(trigger.focusNode!.hasFocus, isTrue);
        expect(find.semantics.byLabel('后台操作'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('popover content stays above keyboard and is scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 300),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: KoiPopover(
            child: const Text('打开资料'),
            builder: (context, close) => Column(
              children: [
                const TextField(decoration: InputDecoration(labelText: '资料名称')),
                const Text('长中文说明用于检查浮层缩放后的阅读与滚动。'),
                TextButton(onPressed: close, child: const Text('完成')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开资料'));
    await tester.pumpAndSettle();
    final viewport = find
        .ancestor(
          of: find.text('完成'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(tester.getRect(viewport).bottom, lessThanOrEqualTo(284));
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late popover close is safe after closing or removing its owner',
    (tester) async {
      late VoidCallback close;
      final outside = FocusNode();
      addTearDown(outside.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: outside,
                  onPressed: () {},
                  child: const Text('后续操作'),
                ),
                KoiPopover(
                  child: const Text('面板'),
                  builder: (context, onClose) {
                    close = onClose;
                    return const Text('无交互内容');
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('面板'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(outside.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      outside.requestFocus();
      await tester.pump();
      close();
      await tester.pump();
      expect(outside.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system Back closes the popover before leaving its page', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('首页')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: KoiPopover(
            child: const Text('打开操作'),
            builder: (_, close) =>
                TextButton(onPressed: close, child: const Text('关闭操作')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开操作'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('关闭操作'), findsNothing);
    expect(find.text('打开操作'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('system Back closes a menu before leaving its page', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('首页')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: KoiMenu(
            items: [KoiMenuItem(label: '执行', onSelected: () {})],
            child: const Text('菜单入口'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜单入口'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('执行'), findsNothing);
    expect(find.text('菜单入口'), findsOneWidget);
    final trigger = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '菜单入口'),
    );
    expect(trigger.focusNode!.hasFocus, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('menu trigger exposes one label and expanded state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KoiMenu(
              label: '工作区设置',
              items: [KoiMenuItem(label: '主题', onSelected: () {})],
              child: const Text('工作区设置'),
            ),
          ),
        ),
      );
      final trigger = find.widgetWithText(TextButton, '工作区设置');
      expect(
        tester.getSemantics(trigger),
        matchesSemantics(
          label: '工作区设置',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
        ),
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(trigger).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(trigger).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });
}
