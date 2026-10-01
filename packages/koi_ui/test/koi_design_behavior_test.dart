import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  for (final density in KoiDensity.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$density $brightness grows controls for large Chinese text',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var activated = 0;
          var query = '';
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(density: density, brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      KoiToolbar(
                        actions: [
                          FilledButton(
                            onPressed: () => activated++,
                            child: const Text('执行中文操作'),
                          ),
                          const OutlinedButton(
                            onPressed: null,
                            child: Text('禁用操作'),
                          ),
                        ],
                      ),
                      KoiSearchField(
                        hintText: '搜索资料',
                        onChanged: (value) => query = value,
                      ),
                      KoiSelectableListTile(
                        title: const Text('较长的中文资料名称需要正确换行'),
                        onTap: () => activated++,
                      ),
                      const KoiPropertyRow(
                        label: '来源',
                        value: Text('这是可以换行的很长中文说明，不能出现截断与横向溢出。'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('执行中文操作'));
          await tester.enterText(find.byType(KoiSearchField), '中文');
          await tester.tap(find.text('较长的中文资料名称需要正确换行'));
          expect(activated, 2);
          expect(query, '中文');
          expect(
            tester.getSize(find.byType(KoiSelectableListTile)).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'comfortable targets stay large and compact selection retains focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget host(KoiDensity density) => MaterialApp(
        theme: AppTheme.build(density: density),
        home: Scaffold(
          body: Column(
            children: [
              KoiSelectableListTile(
                title: const Text('已选资料'),
                selected: true,
                focusNode: focus,
                onTap: () {},
              ),
              FilledButton(onPressed: () {}, child: const Text('操作')),
            ],
          ),
        ),
      );
      await tester.pumpWidget(host(KoiDensity.comfortable));
      final comfortableHeight = tester
          .getSize(find.byType(KoiSelectableListTile))
          .height;
      expect(comfortableHeight, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.pumpWidget(host(KoiDensity.compact));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(KoiSelectableListTile)).height,
        lessThan(comfortableHeight),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.selected, isTrue);
      expect(
        (tile.shape! as RoundedRectangleBorder).side.color,
        AppTheme.light.colorScheme.primary,
      );
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'reading pane bounds wide content and new recipes work in Material hosts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KoiReadingPane(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KoiToolbar(actions: [Text('工具栏')]),
                  KoiSearchField(initialValue: '原有搜索', hintText: '搜索'),
                  KoiPropertyRow(label: '标题', value: Text('中文资料')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(KoiSearchField)).width,
        lessThanOrEqualTo(800),
      );
      expect(find.text('原有搜索'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
