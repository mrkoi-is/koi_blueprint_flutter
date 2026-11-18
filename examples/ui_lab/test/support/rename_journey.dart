import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_lab/main.dart';

/// The same App-level contract runs in the VM and in real Chrome.
void renameJourneyTests() {
  testWidgets(
    'rename commits trimmed name, survives navigation, rejects empty, '
    'and cancel preserves the committed value',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KoiUiLabApp());

      Future<void> tap(Finder target) async {
        expect(target, findsOneWidget);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(tester.takeException(), isNull);
      }

      final dialog = find.byType(AlertDialog);
      final field = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('catalog-rename')),
      );
      Finder action(String text) =>
          find.descendant(of: dialog, matching: find.text(text));
      String readName() => tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text;

      await tap(find.text('标准组件'));
      await tap(find.text('反馈'));
      expect(find.text('当前工作区：产品设计；排序：最近更新'), findsOneWidget);
      await tap(find.text('重命名工作区'));
      expect(readName(), '产品设计');
      await tester.enterText(field, '  AI 闭环工作区  ');
      await tap(action('确认重命名'));
      expect(dialog, findsNothing);
      expect(find.text('当前工作区：AI 闭环工作区；排序：最近更新'), findsOneWidget);

      await tap(find.text('工作区演示'));
      await tap(find.text('标准组件'));
      await tap(find.text('重命名工作区'));
      expect(readName(), 'AI 闭环工作区');
      await tester.enterText(field, '   ');
      await tap(action('确认重命名'));
      expect(dialog, findsOneWidget);
      expect(find.text('名称不能为空'), findsOneWidget);
      await tester.enterText(field, '不应提交的名称');
      await tap(action('取消重命名'));
      expect(find.text('当前工作区：AI 闭环工作区；排序：最近更新'), findsOneWidget);
      await tap(find.text('重命名工作区'));
      expect(readName(), 'AI 闭环工作区');
      await tap(action('取消重命名'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
