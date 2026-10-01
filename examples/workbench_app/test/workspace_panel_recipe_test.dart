import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_panels.dart';

import 'presentation_support.dart';
import 'workspace_presentation_test.dart' show closeApp;

import 'package:workbench_app/app.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_save_status.dart';

void main() {
  testWidgets('sidebar headers align and scrolling restores across views', (
    tester,
  ) async {
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => MemoryStorage(
        WorkspaceSnapshot(
          documents: [
            for (var i = 0; i < 100; i++)
              WorkspaceDocument(id: '$i', title: '资料 $i', text: ''),
          ],
        ),
      ),
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final index = ValueNotifier(0);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: bootstrap.container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                height: 400,
                child: ValueListenableBuilder<int>(
                  valueListenable: index,
                  builder: (_, value, _) => WorkspaceSidebar(index: value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final textOrigin = tester.getTopLeft(find.text('文本资料'));
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    index.value = 1;
    await tester.pumpAndSettle();
    final mediaOrigin = tester.getTopLeft(find.text('媒体分类'));
    index.value = 2;
    await tester.pumpAndSettle();
    final taskOrigin = tester.getTopLeft(find.text('任务概览'));
    index.value = 0;
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    debugPrint(
      'AUDIT heading origins text=$textOrigin media=$mediaOrigin tasks=$taskOrigin; scroll before=$before after=$after',
    );
    expect(textOrigin, mediaOrigin);
    expect(taskOrigin, textOrigin);
    expect(before, greaterThan(0));
    expect(after, before);
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    bootstrap.disposeAsync().then((_) => closed = true);
    for (var i = 0; i < 30 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(closed, isTrue);
    index.dispose();
  });

  testWidgets('host restores sidebar through drawer and inline transitions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => MemoryStorage(
        WorkspaceSnapshot(
          documents: [
            for (var i = 0; i < 100; i++)
              WorkspaceDocument(id: '$i', title: '资料 $i', text: '正文'),
          ],
        ),
      ),
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('sidebar-text-scroll'));
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    await tester.drag(list, const Offset(0, -450));
    await tester.pumpAndSettle();
    final before = offset();
    final router = bootstrap.router;
    final preview = bootstrap.preview;
    tester.view.physicalSize = const Size(800, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换资料侧栏'));
    await tester.pumpAndSettle();
    expect(offset(), before);
    tester.state<ScaffoldState>(find.byType(Scaffold)).closeDrawer();
    await tester.pumpAndSettle();
    // Moving back to the expanded frame removes the drawer and recreates the panel.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(offset(), before);
    expect(bootstrap.router, same(router));
    expect(bootstrap.preview, same(preview));
    expect(tester.takeException(), isNull);
    await closeApp(tester, bootstrap);
  });

  testWidgets(
    'saving feedback retains dirty revision and exposes failure and retry',
    (tester) async {
      final storage = MemoryStorage(
        const WorkspaceSnapshot(
          documents: [WorkspaceDocument(id: 'a', title: '资料', text: '正文')],
        ),
      );
      final bootstrap = await WorkbenchBootstrap.create(
        openStorage: () async => storage,
        fileImportPort: CancelImport(),
        createPlayback: FakePlayback.new,
      );
      bootstrap.session.editDocument('a', '新内容');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: bootstrap.container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final snapshot =
                      ref.watch(workspaceStateProvider).value?.snapshot ??
                      bootstrap.session.state.snapshot;
                  return WorkspaceSaveStatus(
                    document: snapshot.documents.single,
                    includeCount: true,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('未保存'), findsOneWidget);
      final gate = Completer<void>();
      storage.repository.saveGate = gate.future;
      unawaited(bootstrap.session.save());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('工作区保存中'), findsOneWidget);
      bootstrap.session.editDocument('a', '提交期间继续编辑');
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('未保存'), findsOneWidget);
      storage.repository.saveGate = null;
      storage.repository.failSave = true;
      unawaited(bootstrap.session.save());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('工作区保存失败'), findsOneWidget);
      expect(find.textContaining('未保存'), findsOneWidget);
      storage.repository.failSave = false;
      unawaited(bootstrap.session.save());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('已保存'), findsOneWidget);
      expect(find.textContaining('工作区保存失败'), findsNothing);
      await closeApp(tester, bootstrap);
    },
  );
  testWidgets(
    'document and asset details share heading and property roles at 200 percent',
    (tester) async {
      final bootstrap = await WorkbenchBootstrap.create(
        openStorage: () async => MemoryStorage(
          const WorkspaceSnapshot(
            documents: [
              WorkspaceDocument(id: 'a', title: '中文资料.md', text: '正文'),
            ],
            assets: [
              WorkspaceAsset(
                id: 'image',
                name: '中文素材.png',
                kind: MediaKind.image,
                storageKey: 'image',
                byteLength: 120,
              ),
            ],
            preferences: WorkspacePreferences(
              selectedDocumentId: 'a',
              selectedAssetId: 'image',
            ),
          ),
        ),
        fileImportPort: CancelImport(),
        createPlayback: FakePlayback.new,
      );
      final index = ValueNotifier(0);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: bootstrap.container,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 280,
                  height: 400,
                  child: ValueListenableBuilder<int>(
                    valueListenable: index,
                    builder: (_, value, _) => WorkspaceDetails(index: value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.text('资料详情'));
      expect(tester.widget<Text>(find.text('名称')).style!.fontSize, 12);
      index.value = 1;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('素材详情')), origin);
      expect(tester.widget<Text>(find.text('名称')).style!.fontSize, 12);
      expect(
        DefaultTextStyle.of(tester.element(find.text('中文素材.png')))
            .style
            .fontSize,
        14,
      );
      expect(find.text('大小'), findsOneWidget);
      expect(find.text('类型'), findsOneWidget);
      expect(find.text('缩略图状态'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeApp(tester, bootstrap);
      index.dispose();
    },
  );
}
