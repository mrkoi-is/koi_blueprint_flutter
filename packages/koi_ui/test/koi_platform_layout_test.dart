import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final trailing in [false, true]) {
      testWidgets(
        '$direction trailing=$trailing follows physical resize input',
        (tester) async {
          var changed = 280.0;
          await tester.pumpWidget(
            _splitHost(
              direction: direction,
              trailing: trailing,
              onWidthChanged: (value) => changed = value,
            ),
          );
          final handle = find.bySemanticsLabel('调整侧栏宽度');
          final primaryOnRight = trailing != (direction == TextDirection.rtl);
          final initialX = tester.getTopLeft(handle).dx;
          await tester.drag(handle, const Offset(40, 0));
          await tester.pump();
          expect(tester.getTopLeft(handle).dx, initialX + 40);
          expect(changed, primaryOnRight ? 240 : 320);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          expect(tester.getTopLeft(handle).dx, initialX + 30);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(tester.getTopLeft(handle).dx, initialX + 40);

          await tester.sendKeyEvent(LogicalKeyboardKey.home);
          await tester.pump();
          expect(changed, 160);
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.pump();
          expect(changed, 480);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'resize semantics change width independent of reading direction',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var changed = 280.0;
      await tester.pumpWidget(
        _splitHost(
          direction: TextDirection.rtl,
          onWidthChanged: (value) => changed = value,
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('调整侧栏宽度'));
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.increase,
      );
      await tester.pump();
      expect(changed, 290);
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.decrease,
      );
      await tester.pump();
      expect(changed, 280);
      semantics.dispose();
    },
  );

  for (final density in KoiDensity.values) {
    testWidgets('$density split owns its target without covering pane actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var primaryTaps = 0;
      var secondaryTaps = 0;
      var changed = 280.0;
      await tester.pumpWidget(
        _splitHost(
          density: density,
          primary: GestureDetector(
            key: const ValueKey('primary-pane'),
            behavior: HitTestBehavior.opaque,
            onTap: () => primaryTaps++,
            child: const SizedBox.expand(),
          ),
          secondary: GestureDetector(
            key: const ValueKey('secondary-pane'),
            behavior: HitTestBehavior.opaque,
            onTap: () => secondaryTaps++,
            child: const SizedBox.expand(),
          ),
          onWidthChanged: (value) => changed = value,
        ),
      );
      final handle = find.bySemanticsLabel('调整侧栏宽度');
      final target = tester.getRect(handle);
      final expectedWidth = density == KoiDensity.comfortable ? 48.0 : 12.0;
      expect(target.width, expectedWidth);
      expect(tester.getSemantics(handle).rect.width, expectedWidth);
      final primary = find.byKey(const ValueKey('primary-pane'));
      final secondary = find.byKey(const ValueKey('secondary-pane'));
      expect(tester.getRect(primary).right, target.left);
      expect(tester.getRect(secondary).left, target.right);

      // A drag near the target's edge must hit the resize control, not a pane.
      await tester.dragFrom(
        Offset(target.left + 2, target.center.dy),
        const Offset(40, 0),
      );
      await tester.pump();
      expect(changed, 320);
      expect(primaryTaps, 0);
      expect(secondaryTaps, 0);
      await tester.tapAt(
        tester.getRect(primary).centerRight - const Offset(2, 0),
      );
      await tester.tapAt(
        tester.getRect(secondary).centerLeft + const Offset(2, 0),
      );
      expect(primaryTaps, 1);
      expect(secondaryTaps, 1);
      semantics.dispose();
    });
  }

  testWidgets('frame rail targets stay 48 px in both densities and themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    for (final (brightness, density) in [
      for (final brightness in Brightness.values)
        for (final density in KoiDensity.values) (brightness, density),
    ]) {
      var selected = '';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: brightness, density: density),
          home: KoiWorkbenchFrame(
            selectedId: 'text',
            onDestinationSelected: (value) => selected = value,
            destinations: const [
              KoiNavigationDestination(
                id: 'text',
                label: '文本资料',
                icon: Icons.description,
              ),
              KoiNavigationDestination(
                id: 'media',
                label: '媒体素材',
                icon: Icons.image,
              ),
            ],
            sidebar: const Text('资料列表'),
            body: const Text('正文'),
            detail: const Text('详情'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Edge targets can be skipped by the generic guideline. Measure them.
      for (final label in ['文本资料', '媒体素材']) {
        final destination = find.bySemanticsLabel(RegExp('^$label\\n'));
        final target = tester.getSemantics(destination).rect;
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
      }
      final media = find.bySemanticsLabel(RegExp(r'^媒体素材\n'));
      await tester.tapAt(tester.getBottomLeft(media) + const Offset(32, -1));
      expect(selected, 'media');
      if (density == KoiDensity.comfortable) {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('reduced motion paints the splitter focus state immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_splitHost(disableAnimations: true));
    final grip = find.byKey(const ValueKey('koi-split-grip'));
    Color paintedGripColor() =>
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: grip,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color!;
    expect(paintedGripColor(), Colors.transparent);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      paintedGripColor(),
      AppTheme.light.extension<KoiThemeTokens>()!.dropIndicator,
    );
    expect(tester.widget<AnimatedContainer>(grip).duration, Duration.zero);
  });

  for (final width in [320.0, 600.0, 1440.0]) {
    for (final density in KoiDensity.values) {
      testWidgets(
        '$width $density nested routes preserve exported workbench semantics',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.build(density: density),
                home: Scaffold(
                  body: KoiWorkbenchFrame(
                    showHeader: false,
                    selectedId: 'text',
                    onDestinationSelected: (_) {},
                    destinations: const [
                      KoiNavigationDestination(
                        id: 'text',
                        label: '文本资料',
                        icon: Icons.description,
                      ),
                      KoiNavigationDestination(
                        id: 'media',
                        label: '媒体素材',
                        icon: Icons.image,
                      ),
                    ],
                    navigationTrailing: const KoiMenu(
                      label: '工作区设置',
                      items: [],
                      child: Icon(Icons.settings),
                    ),
                    sidebar: Column(
                      children: [
                        const Text('资料列表'),
                        TextButton(onPressed: () {}, child: const Text('选择资料')),
                      ],
                    ),
                    detail: const Text('详情属性'),
                    body: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: TextField(
                            decoration: InputDecoration(labelText: '正文输入'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            // Traverse the exported root tree. Widget semantics finders can
            // still locate nodes that a nested Navigator has blocked from it.
            for (final label in ['文本资料', '媒体素材']) {
              expect(
                find.semantics.byLabel(RegExp('^$label(?:\\n|\$)')),
                findsOneWidget,
              );
            }
            expect(find.semantics.byLabel('工作区设置'), findsOneWidget);
            expect(find.semantics.byLabel('正文输入'), findsOneWidget);
            if (width >= 1024) {
              expect(find.semantics.byLabel('资料列表'), findsOneWidget);
              expect(find.semantics.byLabel('选择资料'), findsOneWidget);
              expect(find.semantics.byLabel('详情属性'), findsOneWidget);
              for (final label in ['调整侧栏宽度', '调整详情宽度']) {
                final handles = find.semantics.byLabel(label);
                expect(handles, findsOneWidget);
                final node = handles.evaluate().single;
                expect(
                  node.rect.width,
                  density == KoiDensity.comfortable ? 48 : 12,
                );
                expect(node.rect.height, lessThan(800));
                expect(
                  node.getSemanticsData().hasAction(SemanticsAction.focus),
                  isTrue,
                );
                expect(
                  node.getSemanticsData().hasAction(SemanticsAction.increase),
                  isTrue,
                );
                var descendants = 0;
                node.visitChildren((_) {
                  descendants++;
                  return true;
                });
                expect(descendants, 0, reason: 'A resize handle owns no pane');
              }
            }
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

Widget _splitHost({
  TextDirection direction = TextDirection.ltr,
  bool trailing = false,
  KoiDensity density = KoiDensity.comfortable,
  bool disableAnimations = false,
  Widget primary = const Text('侧栏'),
  Widget secondary = const Text('正文'),
  ValueChanged<double>? onWidthChanged,
}) => MaterialApp(
  theme: AppTheme.build(density: density),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 400,
      child: KoiResizableSplitView(
        primary: primary,
        secondary: secondary,
        primaryOnTrailing: trailing,
        onWidthChanged: onWidthChanged,
      ),
    ),
  ),
);
