import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  testWidgets(
    'touch mouse and keyboard preserve editor state in automatic mode',
    (tester) async {
      final text = TextEditingController(text: 'mixed input');
      final focus = FocusNode();
      addTearDown(text.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        KoiInputDensity(
          builder: (context, density) => MaterialApp(
            theme: AppTheme.build(density: density),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Column(
                children: [
                  Text(density.name),
                  TextField(controller: text, focusNode: focus),
                  FilledButton(onPressed: () {}, child: const Text('Action')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('comfortable'), findsOneWidget);
      focus.requestFocus();
      // Web applies select-all-on-focus asynchronously. Establish an explicit
      // selection only after focus settles, then verify the input switch.
      await tester.pumpAndSettle();
      text.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(20, 20));
      await mouse.moveTo(const Offset(30, 20));
      await tester.pump();
      expect(find.text('compact'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(
        text.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('compact'), findsOneWidget);
      final touch = await tester.createGesture(kind: PointerDeviceKind.touch);
      await touch.down(const Offset(400, 400));
      await touch.up();
      await tester.pump();
      expect(find.text('comfortable'), findsOneWidget);
      expect(text.text, 'mixed input');
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );

  testWidgets('manual density wins and returning to auto uses the last input', (
    tester,
  ) async {
    Widget host(KoiDensity? density) => KoiInputDensity(
      density: density,
      builder: (context, effective) => MaterialApp(
        home: Scaffold(body: Center(child: Text(effective.name))),
      ),
    );
    await tester.pumpWidget(host(KoiDensity.compact));
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.text('compact'), findsOneWidget);
    await tester.pumpWidget(host(null));
    expect(find.text('comfortable'), findsOneWidget);
    await tester.pumpWidget(host(KoiDensity.comfortable));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(20, 20));
    await mouse.moveTo(const Offset(30, 20));
    await tester.pump();
    expect(find.text('comfortable'), findsOneWidget);
    await tester.pumpWidget(host(null));
    expect(find.text('compact'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('pen input and large text retain touch-sized controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      KoiInputDensity(
        builder: (context, density) => MaterialApp(
          theme: AppTheme.build(density: density),
          home: Scaffold(
            body: Column(
              children: [
                Text(density.name),
                FilledButton(onPressed: () {}, child: const Text('確認操作')),
              ],
            ),
          ),
        ),
      ),
    );
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(const Offset(200, 300));
    await pen.up();
    await tester.pump();
    expect(find.text('comfortable'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}
