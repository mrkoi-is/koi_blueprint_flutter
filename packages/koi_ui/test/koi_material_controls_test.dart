import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final density in KoiDensity.values) {
      final theme = AppTheme.build(brightness: brightness, density: density);

      testWidgets(
        '$brightness $density standard buttons focus and activate once',
        (tester) async {
          final focus = List.generate(6, (_) => FocusNode());
          addTearDown(() {
            for (final node in focus) {
              node.dispose();
            }
          });
          final counts = List.filled(6, 0);
          final buttonKeys = List.generate(
            6,
            (index) => ValueKey('button-$index'),
          );
          await tester.pumpWidget(
            _host(
              theme,
              Wrap(
                children: [
                  FilledButton(
                    key: buttonKeys[0],
                    focusNode: focus[0],
                    onPressed: () => counts[0]++,
                    child: const Text('主要操作'),
                  ),
                  ElevatedButton(
                    key: buttonKeys[1],
                    focusNode: focus[1],
                    onPressed: () => counts[1]++,
                    child: const Text('浮层操作'),
                  ),
                  OutlinedButton(
                    key: buttonKeys[2],
                    focusNode: focus[2],
                    onPressed: () => counts[2]++,
                    child: const Text('次要操作'),
                  ),
                  TextButton(
                    key: buttonKeys[3],
                    focusNode: focus[3],
                    onPressed: () => counts[3]++,
                    child: const Text('文字操作'),
                  ),
                  IconButton(
                    key: buttonKeys[4],
                    focusNode: focus[4],
                    tooltip: '图标操作',
                    onPressed: () => counts[4]++,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  FilledButton.tonal(
                    key: buttonKeys[5],
                    focusNode: focus[5],
                    onPressed: () => counts[5]++,
                    child: const Text('柔和操作'),
                  ),
                  const FilledButton(onPressed: null, child: Text('不可用操作')),
                ],
              ),
            ),
          );
          for (var index = 0; index < focus.length; index++) {
            focus[index].requestFocus();
            await tester.pumpAndSettle();
            expect(focus[index].hasFocus, isTrue);
            expect(
              tester.getSize(find.byKey(buttonKeys[index])).height,
              greaterThanOrEqualTo(density == KoiDensity.compact ? 32 : 48),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(counts[index], 1);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(counts[index], 2);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(
            focus.first.hasFocus,
            isTrue,
            reason: 'Tab skips disabled action',
          );
          await tester.tap(find.text('不可用操作'));
          expect(counts, everyElement(2));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '$brightness $density form keeps Chinese draft through validation at 200%',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final draft = TextEditingController(text: '中文草稿');
          final disabled = TextEditingController(text: '不可编辑的中文资料');
          addTearDown(draft.dispose);
          addTearDown(disabled.dispose);
          final form = GlobalKey<FormState>();
          var saved = 0;
          await tester.pumpWidget(
            _host(
              theme,
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const ValueKey('draft'),
                      controller: draft,
                      decoration: const InputDecoration(labelText: '资料名称'),
                      validator: (value) => (value?.length ?? 0) < 8
                          ? '请输入至少八个字符，原来的中文内容会保留。'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('disabled-input'),
                      controller: disabled,
                      enabled: false,
                      decoration: const InputDecoration(labelText: '只读来源'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      children: [
                        FilledButton(
                          onPressed: () {
                            if (form.currentState!.validate()) saved++;
                          },
                          child: const Text('验证并保存资料'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              textScale: 2,
            ),
          );
          await tester.tap(find.text('验证并保存资料'));
          await tester.pumpAndSettle();
          expect(find.textContaining('请输入至少八个字符'), findsOneWidget);
          expect(draft.text, '中文草稿');
          expect(saved, 0);
          final disabledField = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('disabled-input')),
              matching: find.byType(TextField),
            ),
          );
          expect(disabledField.enabled, isFalse);
          expect(disabled.text, '不可编辑的中文资料');
          expect(
            theme.inputDecorationTheme.disabledBorder!.borderSide.color,
            isNot(theme.inputDecorationTheme.enabledBorder!.borderSide.color),
          );
          await tester.enterText(
            find.byKey(const ValueKey('draft')),
            '可以保存的中文资料名称',
          );
          await tester.tap(find.text('验证并保存资料'));
          await tester.pumpAndSettle();
          expect(saved, 1);
          expect(find.textContaining('请输入至少八个字符'), findsNothing);
          expect(draft.text, '可以保存的中文资料名称');
          expect(tester.takeException(), isNull);
        },
      );

      test('$brightness $density disabled wins over selection and focus', () {
        const disabled = {WidgetState.disabled};
        const combined = {
          WidgetState.disabled,
          WidgetState.selected,
          WidgetState.focused,
          WidgetState.hovered,
          WidgetState.pressed,
          WidgetState.error,
        };
        for (final property in <WidgetStateProperty<Color?>?>[
          theme.checkboxTheme.fillColor,
          theme.checkboxTheme.checkColor,
          theme.radioTheme.fillColor,
          theme.switchTheme.trackColor,
          theme.switchTheme.thumbColor,
          theme.switchTheme.trackOutlineColor,
          theme.textButtonTheme.style!.foregroundColor,
          theme.textButtonTheme.style!.overlayColor,
          theme.menuButtonTheme.style!.foregroundColor,
          theme.menuButtonTheme.style!.overlayColor,
          theme.segmentedButtonTheme.style!.foregroundColor,
        ]) {
          expect(property!.resolve(combined), property.resolve(disabled));
        }
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.menuButtonTheme.style!,
          theme.segmentedButtonTheme.style!,
        ]) {
          expect(style.side!.resolve(combined), style.side!.resolve(disabled));
        }
      });
    }
  }

  testWidgets(
    'standard selection controls keep values and ignore disabled input',
    (tester) async {
      var checked = false;
      var switched = false;
      var radio = 'text';
      var changes = 0;
      final checkboxFocus = FocusNode();
      final radioFocus = FocusNode();
      addTearDown(checkboxFocus.dispose);
      addTearDown(radioFocus.dispose);
      await tester.pumpWidget(
        _host(
          AppTheme.light,
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                Checkbox(
                  key: const ValueKey('enabled-checkbox'),
                  semanticLabel: '保存草稿',
                  focusNode: checkboxFocus,
                  value: checked,
                  onChanged: (value) => setState(() {
                    checked = value!;
                    changes++;
                  }),
                ),
                const Checkbox(
                  key: ValueKey('disabled-checkbox'),
                  semanticLabel: '不可修改权限',
                  value: true,
                  onChanged: null,
                ),
                Switch(
                  key: const ValueKey('enabled-switch'),
                  value: switched,
                  onChanged: (value) => setState(() {
                    switched = value;
                    changes++;
                  }),
                ),
                const Switch(
                  key: ValueKey('disabled-switch'),
                  value: true,
                  onChanged: null,
                ),
                RadioGroup<String>(
                  groupValue: radio,
                  onChanged: (value) => setState(() {
                    radio = value!;
                    changes++;
                  }),
                  child: Row(
                    children: [
                      Radio<String>(value: 'text', focusNode: radioFocus),
                      const Radio<String>(value: 'media'),
                      const Radio<String>(value: 'unavailable', enabled: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      checkboxFocus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(checked, isTrue);
      expect(changes, 1);
      await tester.tap(find.byKey(const ValueKey('enabled-switch')));
      await tester.pumpAndSettle();
      expect(switched, isTrue);
      expect(changes, 2);
      radioFocus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(radio, 'media');
      expect(changes, 3);
      await tester.tap(find.byKey(const ValueKey('disabled-checkbox')));
      await tester.tap(find.byKey(const ValueKey('disabled-switch')));
      await tester.tap(
        find.byWidgetPredicate((widget) {
          return widget is Radio<String> && widget.value == 'unavailable';
        }),
      );
      await tester.pumpAndSettle();
      expect(changes, 3);
      expect(radio, 'media');
      for (final type in [Checkbox, Switch, Radio<String>]) {
        for (final element in find.byType(type).evaluate()) {
          expect(
            tester.getSize(find.byWidget(element.widget)).height,
            greaterThanOrEqualTo(48),
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('checked menu reflects owner state and restores trigger focus', (
    tester,
  ) async {
    var checked = false;
    var activations = 0;
    await tester.pumpWidget(
      _host(
        AppTheme.dark,
        StatefulBuilder(
          builder: (context, setState) => KoiMenu(
            label: '显示设置',
            items: [
              KoiMenuItem(
                label: '显示详情',
                checked: checked,
                onSelected: () => setState(() {
                  checked = !checked;
                  activations++;
                }),
              ),
              KoiMenuItem(
                label: '禁用的选中项',
                checked: true,
                enabled: false,
                onSelected: () => activations++,
              ),
            ],
            child: const Text('显示设置'),
          ),
        ),
      ),
    );
    final trigger = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '显示设置'),
    );
    trigger.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxMenuButton>(
            find.widgetWithText(CheckboxMenuButton, '显示详情'),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.text('禁用的选中项'));
    expect(activations, 0);
    await tester.tap(find.text('显示详情'));
    await tester.pumpAndSettle();
    expect(activations, 1);
    expect(checked, isTrue);
    expect(find.text('显示详情'), findsNothing);
    expect(trigger.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxMenuButton>(
            find.widgetWithText(CheckboxMenuButton, '显示详情'),
          )
          .value,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('显示详情'), findsNothing);
    expect(trigger.focusNode!.hasFocus, isTrue);
    expect(activations, 1);
  });

  testWidgets(
    'menu shortcut hint adds no command handler or duplicate action',
    (tester) async {
      var commands = 0;
      var menuActivations = 0;
      const shortcut = SingleActivator(LogicalKeyboardKey.keyK, control: true);
      await tester.pumpWidget(
        _host(
          AppTheme.light,
          CallbackShortcuts(
            bindings: {shortcut: () => commands++},
            child: KoiMenu(
              label: '命令菜单',
              items: [
                KoiMenuItem(
                  label: '打开命令',
                  shortcut: shortcut,
                  onSelected: () => menuActivations++,
                ),
              ],
              child: const Text('命令菜单'),
            ),
          ),
        ),
      );
      final trigger = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '命令菜单'),
      );
      trigger.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _controlK(tester);
      expect(
        commands,
        1,
        reason: 'Only the host registers the closed-menu shortcut',
      );
      expect(menuActivations, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('K'), findsOneWidget);
      await _controlK(tester);
      expect(
        commands,
        2,
        reason: 'Opening the menu must not duplicate the handler',
      );
      expect(menuActivations, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(trigger.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开命令'));
      await tester.pumpAndSettle();
      expect(commands, 2);
      expect(menuActivations, 1);
      expect(find.text('打开命令'), findsNothing);
    },
  );

  testWidgets('standard table animates into Koi and grows for Chinese text', (
    tester,
  ) async {
    const name = '需要换行的中文资料名称';
    var selected = false;
    Widget table(ThemeData theme, double textScale) => _host(
      theme,
      StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [DataColumn(label: Text('资料名称'))],
            rows: [
              DataRow(
                selected: selected,
                onSelectChanged: (value) => setState(() => selected = value!),
                cells: const [
                  DataCell(SizedBox(width: 180, child: Text(name))),
                ],
              ),
            ],
          ),
        ),
      ),
      textScale: textScale,
    );
    await tester.pumpWidget(table(ThemeData(useMaterial3: true), 1));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    final initialTextHeight = tester.getSize(find.text(name)).height;
    await tester.pumpWidget(table(AppTheme.dark, 2));
    // Sample a real AnimatedTheme interpolation, not only the settled result.
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows.single.selected,
      isTrue,
    );
    expect(
      tester.getSize(find.text(name)).height,
      greaterThan(initialTextHeight),
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _host(ThemeData theme, Widget child, {double textScale = 1}) =>
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

Future<void> _controlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}
