import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';

import 'ai_persistence_sandbox.dart';
import '../presentation_support.dart';

/// Cross-platform UI journeys use the real native/IndexedDB storage adapter.
void persistenceHappyTests() {
  testWidgets('W1 UI edits survive complete owner recreation', (tester) async {
    final sandbox = (await tester.runAsync(createRuntimeSandbox))!;
    WorkbenchBootstrap? owner;
    try {
      owner = await _open(tester, sandbox);
      await _mount(tester, owner);
      final id = await _newDocument(tester, owner, '持久化资料', '重新打开的中文草稿');
      await _save(tester, owner);
      await _close(tester, owner);
      owner = null;

      owner = await _open(tester, sandbox);
      await _mount(tester, owner);
      expect(owner.session.state.snapshot.preferences.selectedDocumentId, id);
      expect(find.text('持久化资料'), findsWidgets);
      expect(_editor(tester, id).controller!.text, '重新打开的中文草稿');
      expect(tester.takeException(), isNull);
    } finally {
      if (owner != null) await _close(tester, owner);
      await tester.runAsync(sandbox.dispose);
    }
  });

  testWidgets('W5 documents and distinct storage roots remain isolated', (
    tester,
  ) async {
    final first = (await tester.runAsync(createRuntimeSandbox))!;
    final second = (await tester.runAsync(createRuntimeSandbox))!;
    WorkbenchBootstrap? owner;
    try {
      owner = await _open(tester, first);
      await _mount(tester, owner);
      final a = await _newDocument(tester, owner, '甲资料', '甲内容');
      final b = await _newDocument(tester, owner, '乙资料', '乙内容');
      await tester.tap(find.text('甲资料').first);
      await tester.pumpAndSettle();
      expect(_editor(tester, a).controller!.text, '甲内容');
      await tester.tap(find.text('乙资料').first);
      await tester.pumpAndSettle();
      expect(_editor(tester, b).controller!.text, '乙内容');
      await _save(tester, owner);
      await _close(tester, owner);
      owner = null;

      owner = await _open(tester, second);
      await _mount(tester, owner);
      expect(owner.session.state.snapshot.documents, isEmpty);
      final c = await _newDocument(tester, owner, '独立资料', '独立内容');
      await _save(tester, owner);
      await _close(tester, owner);
      owner = null;

      owner = await _open(tester, first);
      await _mount(tester, owner);
      expect(
        owner.session.state.snapshot.documents.map((d) => d.id),
        containsAll([a, b]),
      );
      expect(find.text('独立资料'), findsNothing);
      await tester.tap(find.text('甲资料').first);
      await tester.pumpAndSettle();
      expect(_editor(tester, a).controller!.text, '甲内容');
      await tester.tap(find.text('乙资料').first);
      await tester.pumpAndSettle();
      expect(_editor(tester, b).controller!.text, '乙内容');
      await _close(tester, owner);
      owner = null;

      owner = await _open(tester, second);
      await _mount(tester, owner);
      expect(owner.session.state.snapshot.documents, hasLength(1));
      expect(find.text('甲资料'), findsNothing);
      expect(_editor(tester, c).controller!.text, '独立内容');
      expect(tester.takeException(), isNull);
    } finally {
      if (owner != null) await _close(tester, owner);
      await tester.runAsync(first.dispose);
      await tester.runAsync(second.dispose);
    }
  });
}

Future<WorkbenchBootstrap> _open(
  WidgetTester tester,
  RuntimeSandbox sandbox,
) async => (await tester.runAsync(() async {
  final preferences = MemoryUiPreferencesStore();
  // Browser flutter_test does not serve InkSparkle's shader asset. Compact
  // density is a supported appearance setting with NoSplash.
  await preferences.write({'density': 'compact', 'locale': 'zh'});
  return WorkbenchBootstrap.create(
    openStorage: sandbox.open,
    openPreferences: () async => preferences,
    fileImportPort: CancelImport(),
    createPlayback: FakePlayback.new,
    initialLocation: '/text',
  );
}))!;

Future<void> _mount(WidgetTester tester, WorkbenchBootstrap owner) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(WorkbenchApp(bootstrap: owner));
  await tester.pumpAndSettle();
  final mountError = tester.takeException();
  if (mountError != null) fail('mount: $mountError');
}

Future<String> _newDocument(
  WidgetTester tester,
  WorkbenchBootstrap owner,
  String title,
  String text,
) async {
  await tester.tap(find.byKey(const ValueKey('new-document')));
  await tester.pumpAndSettle();
  final id = owner.session.state.snapshot.preferences.selectedDocumentId!;
  await tester.tap(find.byTooltip('重命名当前资料'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    title,
  );
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ValueKey('editor-$id')), text);
  await tester.pump();
  final editError = tester.takeException();
  if (editError != null) fail('edit: $editError');
  return id;
}

TextField _editor(WidgetTester tester, String id) =>
    tester.widget<TextField>(find.byKey(ValueKey('editor-$id')));

Future<void> _save(WidgetTester tester, WorkbenchBootstrap owner) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(modifier);
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (owner.session.state.snapshot.documents.any((doc) => doc.dirty) ||
      owner.session.state.saving) {
    if (DateTime.now().isAfter(deadline)) fail('save did not complete');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  final error = owner.session.state.error;
  if (error != null) fail('save error: $error');
}

Future<void> _close(WidgetTester tester, WorkbenchBootstrap owner) async {
  await tester.pumpWidget(const SizedBox());
  var closed = false;
  Object? failure;
  owner.disposeAsync().then(
    (_) => closed = true,
    onError: (Object error) {
      failure = error;
      closed = true;
    },
  );
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!closed && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(closed, isTrue, reason: 'All workspace owners must release');
  expect(failure, isNull);
  await tester.pump();
}
