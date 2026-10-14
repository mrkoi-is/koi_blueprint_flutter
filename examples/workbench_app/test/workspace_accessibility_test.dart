import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'presentation_support.dart';
import 'workspace_presentation_test.dart' show closeApp;

Future<WorkbenchBootstrap> openApp(
  WidgetTester tester,
  WorkspaceSnapshot snapshot, {
  Size size = const Size(1400, 1000),
  double textScale = 1,
  FileImportPort? importPort,
  MemoryStorage? storage,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final bootstrap = await WorkbenchBootstrap.create(
    openStorage: () async => storage ?? MemoryStorage(snapshot),
    fileImportPort: importPort ?? CancelImport(),
    createPlayback: FakePlayback.new,
  );
  await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
  await tester.pumpAndSettle();
  return bootstrap;
}

Finder dialogField() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

void main() {
  testWidgets(
    'media exposes selection, full names and adjustable labeled values',
    (tester) async {
      final semantics = tester.ensureSemantics();

      const name = '完整的中文视频名称用于辅助技术和指针提示.mp4';
      final bootstrap = await openApp(
        tester,
        const WorkspaceSnapshot(
          assets: [
            WorkspaceAsset(
              id: 'video',
              name: name,
              kind: MediaKind.video,
              byteLength: 1,
              storageKey: 'video',
              thumbnailStatus: ThumbnailStatus.ready,
            ),
          ],
          preferences: WorkspacePreferences(
            navId: 'media',
            selectedAssetId: 'video',
          ),
        ),
      );
      final card = tester.getSemantics(find.bySemanticsLabel('视频，$name'));
      expect(
        card,
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          label: '视频，$name',
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(find.byTooltip(name), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      final progress = tester.getSemantics(find.bySemanticsLabel('播放进度'));
      expect(progress.label, '播放进度');
      expect(progress.getSemanticsData().value, '已播放 00:07，共 00:30');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('音量'))
            .getSemanticsData()
            .value,
        '100%',
      );
      final player = bootstrap.preview.playback!;
      await tester.tap(find.byType(Slider).first);
      tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(Slider).first,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is Focus && widget.focusNode != null,
                  ),
                )
                .first,
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      final position = player.position;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(player.position, greaterThan(position));
      tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(Slider).last,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is Focus && widget.focusNode != null,
                  ),
                )
                .first,
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      final volume = player.volume;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(player.volume, lessThan(volume));
      semantics.dispose();
      await closeApp(tester, bootstrap);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'thumbnail read retry stays separate from selection at scale $scale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        const name = '读取失败仍能独立重试的缩略图.png';
        const snapshot = WorkspaceSnapshot(
          assets: [
            WorkspaceAsset(
              id: 'asset',
              name: name,
              kind: MediaKind.image,
              byteLength: 68,
              storageKey: 'original',
              thumbnailKey: 'thumbnail',
              thumbnailStatus: ThumbnailStatus.ready,
            ),
          ],
          preferences: WorkspacePreferences(navId: 'media'),
        );
        final storage = MemoryStorage(snapshot);
        storage.assetStore.failedReads.add('thumbnail');
        storage.assetStore.values['thumbnail'] = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final bootstrap = await openApp(
          tester,
          snapshot,
          storage: storage,
          textScale: scale,
          size: scale == 2 ? const Size(320, 600) : const Size(1400, 1000),
        );
        final select = tester.getSemantics(find.bySemanticsLabel('图片，$name'));
        final retry = tester.getSemantics(
          find.bySemanticsLabel('重试读取缩略图：$name'),
        );
        expect(select.id, isNot(retry.id));
        expect(
          select.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(retry.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(select.getSemanticsData().value, '缩略图读取失败');
        expect(tester.takeException(), isNull);
        final retryButton = find.widgetWithText(TextButton, '重试读取');
        await Scrollable.ensureVisible(
          tester.element(retryButton),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        storage.assetStore.failedReads.clear();
        await tester.tap(retryButton);
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.text('重试读取'), findsNothing);
        expect(find.text('缩略图读取失败'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        expect(
          bootstrap.session.state.snapshot.preferences.selectedAssetId,
          isNull,
          reason: 'Retrying must not trigger the neighboring selection action',
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await closeApp(tester, bootstrap);
      },
    );
  }

  testWidgets(
    'todo controls are named and deletion requires a specific confirmation',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final bootstrap = await openApp(
        tester,
        const WorkspaceSnapshot(
          todos: [WorkspaceTodo(id: 'todo', title: '准备中文素材')],
          preferences: WorkspacePreferences(navId: 'tasks'),
        ),
      );
      expect(tester.getSemantics(find.byType(Checkbox)).label, '准备中文素材');
      expect(
        tester
            .getSemantics(find.byTooltip('重命名待办：准备中文素材'))
            .getSemanticsData()
            .tooltip,
        '重命名待办：准备中文素材',
      );
      expect(
        tester
            .getSemantics(find.byTooltip('删除待办：准备中文素材'))
            .getSemanticsData()
            .tooltip,
        '删除待办：准备中文素材',
      );
      await tester.tap(find.byTooltip('重命名待办：准备中文素材'));
      await tester.pumpAndSettle();
      expect(find.text('待办名称'), findsOneWidget);
      await tester.enterText(dialogField(), '  ');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(find.text('请输入待办名称'), findsOneWidget);
      expect(bootstrap.session.state.snapshot.todos.single.title, '准备中文素材');
      await tester.enterText(dialogField(), '检查中文素材');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bootstrap.session.state.snapshot.todos.single.title, '检查中文素材');
      await tester.tap(find.byTooltip('删除待办：检查中文素材'));
      await tester.pumpAndSettle();
      expect(find.text('删除“检查中文素材”？此操作无法撤销。'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(bootstrap.session.state.snapshot.todos, hasLength(1));
      await tester.tap(find.byTooltip('删除待办：检查中文素材'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(bootstrap.session.state.snapshot.todos, isEmpty);
      semantics.dispose();
      await closeApp(tester, bootstrap);
    },
  );

  testWidgets(
    'document rename keeps invalid input open and supports submit and Escape',
    (tester) async {
      final bootstrap = await openApp(
        tester,
        const WorkspaceSnapshot(
          documents: [WorkspaceDocument(id: 'doc', title: '资料名称', text: '正文')],
          preferences: WorkspacePreferences(selectedDocumentId: 'doc'),
        ),
      );
      await tester.tap(find.byTooltip('重命名当前资料'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(dialogField()).decoration!.labelText,
        '资料名称',
      );
      await tester.enterText(dialogField(), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('请输入资料名称'), findsOneWidget);
      await tester.enterText(dialogField(), '新资料名称');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(bootstrap.session.state.snapshot.documents.single.title, '新资料名称');
      await tester.tap(find.byTooltip('重命名当前资料'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), '不应保存');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bootstrap.session.state.snapshot.documents.single.title, '新资料名称');
      await closeApp(tester, bootstrap);
    },
  );

  testWidgets('job progress exposes processing state and actual byte count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final importer = PendingImport();
    final source = _StreamingSource();
    final bootstrap = await openApp(
      tester,
      const WorkspaceSnapshot(
        preferences: WorkspacePreferences(navId: 'tasks'),
      ),
      importPort: importer,
    );
    final importing = bootstrap.session.importFiles(ImportKind.text);
    await tester.pump();
    await tester.pump();
    var progress = tester
        .getSemantics(find.byType(LinearProgressIndicator))
        .getSemanticsData();
    expect(progress.label, '导入文本资料，处理中，进度暂不可确定');
    importer.result.complete(FilesSelected([source]));
    await tester.pump();
    source.chunks.add([65, 66]);
    await tester.pump();
    await tester.pump();
    progress = tester
        .getSemantics(find.byType(LinearProgressIndicator))
        .getSemanticsData();
    expect(progress.label, '导入文本资料，处理中，2 字节 / 4 字节');
    expect(progress.value, '50');
    source.chunks.add([67, 68]);
    final streamClosed = source.chunks.close();
    var finished = false;
    final finishing = Future.wait([streamClosed, importing])
        .then((_) => finished = true);
    for (var attempt = 0; attempt < 20 && !finished; attempt++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(finished, isTrue);
    await finishing;
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('完成'), findsOneWidget);
    semantics.dispose();
    await closeApp(tester, bootstrap);
  });

  testWidgets(
    'short narrow views handle 200 percent text, pending media and keyboard',
    (tester) async {
      final bootstrap = await openApp(
        tester,
        const WorkspaceSnapshot(
          documents: [
            WorkspaceDocument(
              id: 'doc',
              title: '很长的中文文本资料标题用于验证短小窗口',
              text: '可编辑中文草稿',
            ),
          ],
          todos: [WorkspaceTodo(id: 'todo', title: '很长的中文待办事项也应该可以正常完成和编辑')],
          assets: [
            WorkspaceAsset(
              id: 'pending',
              name: '长中文待生成缩略图视频.mp4',
              kind: MediaKind.video,
              byteLength: 1,
              storageKey: 'pending',
            ),
            WorkspaceAsset(
              id: 'failed',
              name: '长中文失败缩略图视频.mp4',
              kind: MediaKind.video,
              byteLength: 1,
              storageKey: 'failed',
              thumbnailStatus: ThumbnailStatus.failed,
            ),
          ],
          preferences: WorkspacePreferences(selectedDocumentId: 'doc'),
        ),
        size: const Size(320, 600),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(find.byKey(const ValueKey('editor-doc')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const ValueKey('editor-doc')), '短窗口输入');
      await tester.pump();
      expect(bootstrap.session.state.snapshot.documents.single.text, '短窗口输入');
      tester.view.resetViewInsets();
      bootstrap.router.go('/media');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('打开预览生成缩略图'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('缩略图失败'),
        120,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
      bootstrap.router.go('/tasks');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const PageStorageKey('tasks-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('重命名待办：很长的中文待办事项也应该可以正常完成和编辑'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(dialogField(), '新名称');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(bootstrap.session.state.snapshot.todos.single.title, '新名称');
      tester.view.resetViewInsets();
      await closeApp(tester, bootstrap);
    },
  );
}

class _StreamingSource implements ImportSource {
  final chunks = StreamController<List<int>>();
  @override
  String get name => '进度测试.txt';
  @override
  int get byteLength => 4;
  @override
  Stream<List<int>> openRead() => chunks.stream;
  @override
  Future<void> close() async {}
}
