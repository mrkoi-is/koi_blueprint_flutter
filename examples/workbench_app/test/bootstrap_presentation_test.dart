import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

import 'presentation_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
  ]) {
    testWidgets(
      'mounted app saves then unmounts borrowers before exit while ${lifecycle.name}',
      (tester) async {
        final storage = MemoryStorage();
        final bootstrap = await WorkbenchBootstrap.create(
          openStorage: () async => storage,
          fileImportPort: CancelImport(),
          createPlayback: FakePlayback.new,
        );
        final id = bootstrap.session.createDocument(text: '关闭时保留的草稿');
        await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
        await tester.pumpAndSettle();
        final scope = tester.element(find.byType(UncontrolledProviderScope));
        final router = tester.element(find.byType(Router<Object>));
        final borrowersMountedAtClose = <bool>[];
        bootstrap.container.listen(
          Provider<void>((ref) {
            ref.onDispose(() {
              borrowersMountedAtClose.add(scope.mounted || router.mounted);
            });
          }),
          (_, _) {},
        );
        final gate = Completer<void>();
        storage.repository.saveGate = gate.future;
        final closing = tester.binding.handleRequestAppExit();
        final repeated = tester.binding.handleRequestAppExit();
        AppExitResponse? response;
        unawaited(closing.then((value) => response = value));
        await tester.pump();
        expect(response, isNull);
        expect(scope.mounted, isTrue);
        expect(router.mounted, isTrue);
        expect(storage.closes, 0);
        expect(
          bootstrap.container
              .read(workspaceSnapshotProvider)
              .snapshot
              .documents
              .single
              .id,
          id,
        );
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
        await tester.pump();
        expect(
          tester.binding.framesEnabled,
          lifecycle != AppLifecycleState.paused,
        );
        gate.complete();
        await _finishExit(tester, () => response != null);
        expect(response, AppExitResponse.exit);
        expect(borrowersMountedAtClose, [false]);
        expect(scope.mounted, isFalse);
        expect(router.mounted, isFalse);
        expect(storage.closes, 1);
        expect(storage.repository.snapshot.documents.single.text, '关闭时保留的草稿');
        expect(repeated, same(closing));
        // The OS can dispatch lifecycle changes after owners have closed.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await bootstrap.disposeAsync();
        expect(storage.closes, 1);
        expect(tester.takeException(), isNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );
  }

  testWidgets('mounted app cancels failed close and keeps the editor usable', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final id = bootstrap.session.createDocument(text: '保存失败后继续编辑');
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    final scope = tester.element(find.byType(UncontrolledProviderScope));
    storage.repository.failSave = true;
    AppExitResponse? response;
    final failed = tester.binding.handleRequestAppExit();
    unawaited(failed.then((value) => response = value));
    await _finishExit(tester, () => response != null);
    expect(response, AppExitResponse.cancel);
    expect(scope.mounted, isTrue);
    expect(storage.closes, 0);
    expect(bootstrap.preparingToClose.value, isFalse);
    await tester.enterText(find.byKey(ValueKey('editor-$id')), '继续编辑成功');
    await tester.pump();
    expect(bootstrap.session.state.snapshot.documents.single.text, '继续编辑成功');
    storage.repository.failSave = false;
    response = null;
    final retry = tester.binding.handleRequestAppExit();
    expect(retry, isNot(same(failed)));
    unawaited(retry.then((value) => response = value));
    await _finishExit(tester, () => response != null);
    expect(response, AppExitResponse.exit);
    expect(scope.mounted, isFalse);
    expect(storage.repository.snapshot.documents.single.text, '继续编辑成功');
    expect(storage.closes, 1);
    await tester.pumpWidget(const SizedBox());
    await bootstrap.disposeAsync();
    expect(tester.takeException(), isNull);
  });

  testWidgets('late asynchronous observer can cancel before workspace closes', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final id = bootstrap.session.createDocument(text: '其他观察者决定前保持编辑');
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    final scope = tester.element(find.byType(UncontrolledProviderScope));
    var decision = Completer<AppExitResponse>();
    var requests = 0;
    final statesAtDecision = <(bool, bool, int)>[];
    final lateObserver = AppLifecycleListener(
      onExitRequested: () async {
        requests++;
        final response = await decision.future;
        statesAtDecision.add((
          scope.mounted,
          bootstrap.preparingToClose.value,
          storage.closes,
        ));
        return response;
      },
    );
    addTearDown(lateObserver.dispose);
    AppExitResponse? response;
    final canceled = tester.binding.handleRequestAppExit();
    expect(tester.binding.handleRequestAppExit(), same(canceled));
    unawaited(canceled.then((value) => response = value));
    await tester.pump();
    expect(requests, 1);
    expect(response, isNull);
    decision.complete(AppExitResponse.cancel);
    await _finishExit(tester, () => response != null);
    expect(response, AppExitResponse.cancel);
    expect(statesAtDecision, [(true, false, 0)]);
    expect(scope.mounted, isTrue);
    expect(bootstrap.preparingToClose.value, isFalse);
    await tester.enterText(find.byKey(ValueKey('editor-$id')), '取消退出后还能编辑');
    decision = Completer<AppExitResponse>();
    response = null;
    final accepted = tester.binding.handleRequestAppExit();
    unawaited(accepted.then((value) => response = value));
    await tester.pump();
    expect(requests, 2);
    decision.complete(AppExitResponse.exit);
    await _finishExit(tester, () => response != null);
    expect(response, AppExitResponse.exit);
    expect(statesAtDecision, [(true, false, 0), (true, false, 0)]);
    expect(scope.mounted, isFalse);
    expect(storage.closes, 1);
    expect(storage.repository.snapshot.documents.single.text, '取消退出后还能编辑');
    await tester.pumpWidget(const SizedBox());
    await bootstrap.disposeAsync();
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget removal waits for the already pending exit save', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    bootstrap.session.createDocument(text: '卸载也必须等保存结束');
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    storage.repository.saveGate = gate.future;
    AppExitResponse? response;
    unawaited(
      tester.binding.handleRequestAppExit().then((value) => response = value),
    );
    await tester.pump();
    expect(bootstrap.preparingToClose.value, isTrue);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(response, isNull);
    expect(storage.closes, 0);
    gate.complete();
    await _finishExit(tester, () => response != null);
    expect(response, AppExitResponse.exit);
    await bootstrap.disposeAsync();
    expect(storage.closes, 1);
    expect(storage.repository.snapshot.documents.single.text, '卸载也必须等保存结束');
    expect(tester.takeException(), isNull);
  });

  test('synchronous projection reads immediately and rejects events from a rebound session', () async {
    Future<WorkspaceSession> session(String text) async {
      final storage = MemoryStorage();
      final value = WorkspaceSession(
        repository: storage.repository,
        assetStore: storage.assetStore,
        fileImportPort: CancelImport(),
      );
      await value.initialize();
      value.createDocument(text: text);
      return value;
    }

    final first = await session('first');
    final second = await session('second');
    final container = ProviderContainer(
      overrides: [workspaceSessionProvider.overrideWithValue(first)],
    );
    final seen = <WorkspaceState>[];
    container.listen(workspaceSnapshotProvider, (_, next) => seen.add(next));
    expect(
      container.read(workspaceSnapshotProvider).snapshot.documents.single.text,
      'first',
    );
    first.addTodo('queued old event');
    container.updateOverrides([
      workspaceSessionProvider.overrideWithValue(second),
    ]);
    await container.pump();
    expect(
      container.read(workspaceSnapshotProvider).snapshot.documents.single.text,
      'second',
    );
    final count = seen.length;
    first.addTodo('old owner remains usable');
    await container.pump();
    expect(seen.length, count);
    second.addTodo('new owner event');
    await container.pump();
    expect(
      container.read(workspaceSnapshotProvider).snapshot.todos.single.title,
      'new owner event',
    );
    container.dispose();
    first.createDocument(text: 'borrowed owners stay open');
    second.createDocument(text: 'projection never closes owner');
    final closing = second.dispose();
    expect(second.dispose(), same(closing));
    await closing;
    await first.dispose();
  });

  test(
    'late selected files only release inputs after storage has closed',
    () async {
      final storage = MemoryStorage();
      final picker = PendingImport();
      final bootstrap = await WorkbenchBootstrap.create(
        openStorage: () async => storage,
        fileImportPort: picker,
        createPlayback: FakePlayback.new,
      );
      final importing = bootstrap.session.importFiles(ImportKind.text);
      await Future<void>.delayed(Duration.zero);
      expect((await bootstrap.prepareToClose()).succeeded, true);
      await bootstrap.disposeAsync();
      final saves = storage.repository.saves;
      final source = _LateSource();
      picker.result.complete(FilesSelected([source]));
      await importing;
      expect(source.closes, 1);
      expect(source.reads, 0);
      expect(storage.assetStore.values, isEmpty);
      expect(storage.repository.saves, saves);
      expect(storage.repository.snapshot.documents, isEmpty);
    },
  );

  test('close preparation waits for writes, saves all content and reuses pending request', () async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    bootstrap.session.createDocument(text: '关闭前中文草稿');
    bootstrap.session.addTodo('保存待办');
    bootstrap.session.updatePreferences(
      bootstrap.session.state.snapshot.preferences.copyWith(
        themeMode: WorkspaceThemeMode.dark,
      ),
    );
    final gate = Completer<void>();
    storage.repository.saveGate = gate.future;
    final pending = bootstrap.prepareToClose();
    expect(bootstrap.prepareToClose(), same(pending));
    await Future<void>.delayed(Duration.zero);
    expect(bootstrap.preparingToClose.value, isTrue);
    expect(storage.closes, 0);
    expect(() => bootstrap.session.addTodo('迟到修改'), throwsStateError);
    gate.complete();
    expect((await pending).succeeded, isTrue);
    expect(storage.repository.snapshot.documents.single.text, '关闭前中文草稿');
    expect(storage.repository.snapshot.todos.single.title, '保存待办');
    expect(
      storage.repository.snapshot.preferences.themeMode,
      WorkspaceThemeMode.dark,
    );
    await bootstrap.disposeAsync();
    expect(storage.closes, 1);
  });

  test('save failure cancels close, keeps usable owners and permits editing and another close', () async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final id = bootstrap.session.createDocument(text: '失败仍保留');
    storage.repository.failSave = true;
    expect((await bootstrap.prepareToClose()).succeeded, isFalse);
    expect(storage.closes, 0);
    expect(bootstrap.preparingToClose.value, isFalse);
    bootstrap.session.editDocument(id, '继续编辑');
    storage.repository.failSave = false;
    expect((await bootstrap.prepareToClose()).succeeded, isTrue);
    expect(storage.repository.snapshot.documents.single.text, '继续编辑');
    await bootstrap.disposeAsync();
  });

  test('close abandons pending system picker and rejects late file results without storage writes', () async {
    final storage = MemoryStorage();
    final picker = PendingImport();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: picker,
      createPlayback: FakePlayback.new,
    );
    final importing = bootstrap.session.importFiles(ImportKind.text);
    await Future<void>.delayed(Duration.zero);
    expect((await bootstrap.prepareToClose()).succeeded, isTrue);
    expect(storage.repository.snapshot.jobs.single.status, JobStatus.cancelled);
    await bootstrap.disposeAsync();
    picker.result.complete(const ImportCancelled());
    await importing;
    expect(storage.repository.snapshot.documents, isEmpty);
    expect(storage.closes, 1);
  });

  test(
    'initialization failure closes every constructed storage owner',
    () async {
      final storage = MemoryStorage()..repository.failLoad = true;
      await expectLater(
        WorkbenchBootstrap.create(
          openStorage: () async => storage,
          fileImportPort: CancelImport(),
          createPlayback: FakePlayback.new,
        ),
        throwsStateError,
      );
      expect(storage.closes, 1);
    },
  );

  test('router and injected owners close once; borrowed provider does not close session', () async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSessionProvider.overrideWithValue(bootstrap.session),
      ],
    );
    final subscription = container.listen(workspaceStateProvider, (_, _) {});
    await container.read(workspaceStateProvider.future);
    subscription.close();
    container.dispose();
    bootstrap.session.createDocument(text: 'provider is only a borrower');
    final router = bootstrap.router;
    bootstrap.session.addTodo('still alive');
    expect(bootstrap.router, same(router));
    final closing = bootstrap.disposeAsync();
    expect(bootstrap.disposeAsync(), same(closing));
    await closing;
    expect(storage.closes, 1);
    expect(() => bootstrap.session.createDocument(), throwsStateError);
  });

  test('missing bootstrap overrides fail instead of making fake data', () {
    final container = ProviderContainer(retry: (_, _) => null);
    expect(() => container.read(workspaceSessionProvider), throwsA(anything));
    expect(
      () => container.read(mediaPreviewSessionProvider).session,
      throwsA(anything),
    );
    expect(
      () => container.read(navigationHistoryProvider).history,
      throwsA(anything),
    );
    container.dispose();
  });
}

Future<void> _finishExit(WidgetTester tester, bool Function() completed) async {
  for (var attempt = 0; attempt < 20 && !completed(); attempt++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    completed(),
    isTrue,
    reason: 'Exit must finish without a native frame',
  );
  await tester.pump();
}

final class _LateSource implements ImportSource {
  int reads = 0;
  int closes = 0;
  @override
  String get name => 'late.txt';
  @override
  int get byteLength => 4;
  @override
  Stream<List<int>> openRead() {
    reads++;
    return Stream.value([108, 97, 116, 101]);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}
