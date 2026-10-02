import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

import 'presentation_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      () => container.read(mediaPreviewSessionProvider),
      throwsA(anything),
    );
    expect(() => container.read(navigationHistoryProvider), throwsA(anything));
    container.dispose();
  });
}
