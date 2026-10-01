import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/router/workbench_navigation_history.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

import 'presentation_support.dart';

const _snapshot = WorkspaceSnapshot(
  documents: [
    WorkspaceDocument(id: 'a', title: '资料 A'),
    WorkspaceDocument(id: 'b', title: '资料 B'),
  ],
  assets: [
    WorkspaceAsset(
      id: 'video-a',
      name: 'A.mp4',
      kind: MediaKind.video,
      storageKey: 'a',
      byteLength: 1,
    ),
    WorkspaceAsset(
      id: 'video-b',
      name: 'B.mp4',
      kind: MediaKind.video,
      storageKey: 'b',
      byteLength: 1,
    ),
  ],
  preferences: WorkspacePreferences(
    selectedDocumentId: 'a',
    selectedAssetId: 'video-a',
  ),
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<WorkbenchBootstrap> _bootstrap([
  WorkspaceSnapshot snapshot = _snapshot,
]) => WorkbenchBootstrap.create(
  openStorage: () async => MemoryStorage(snapshot),
  fileImportPort: CancelImport(),
  createPlayback: FakePlayback.new,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'history restores view and content; a new visit clears forward branch',
    () async {
      final bootstrap = await _bootstrap();
      addTearDown(bootstrap.disposeAsync);
      final history = bootstrap.history;
      final session = bootstrap.session;
      final router = bootstrap.router;
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedDocumentId: 'b'),
      );
      await _flush();
      expect(history.canGoBack, isTrue);
      var notifications = 0;
      history.addListener(() => notifications++);
      session.editDocument('b', '保存期间继续编辑');
      session.renameDocument('b', '更新标题');
      session.addTodo('更新待办');
      await session.save();
      await _flush();
      expect(notifications, 0);
      router.go('/media');
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedAssetId: 'video-b'),
      );
      await _flush();
      router.go('/tasks');
      history.goBack();
      await _flush();
      expect(router.routeInformationProvider.value.uri.path, '/media');
      expect(session.state.snapshot.preferences.selectedAssetId, 'video-b');
      history.goBack();
      await _flush();
      expect(session.state.snapshot.preferences.selectedAssetId, 'video-a');
      history.goForward();
      await _flush();
      expect(session.state.snapshot.preferences.selectedAssetId, 'video-b');
      router.go('/text');
      await _flush();
      expect(history.canGoForward, isFalse);
      expect(session.state.snapshot.documents.last.text, '保存期间继续编辑');
      expect(bootstrap.router, same(router));
      expect(bootstrap.session, same(session));
      history.goBack();
      history.goBack();
      history.goBack();
      history.goBack();
      await _flush();
      expect(session.state.snapshot.preferences.selectedDocumentId, 'a');
      expect(history.canGoBack, isFalse);
      history.goBack();
      expect(session.state.snapshot.preferences.selectedDocumentId, 'a');
    },
  );

  test(
    'deleted content is skipped and availability updates without page change',
    () async {
      final bootstrap = await _bootstrap();
      addTearDown(bootstrap.disposeAsync);
      final session = bootstrap.session;
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedDocumentId: 'b'),
      );
      await _flush();
      bootstrap.router.go('/tasks');
      session.deleteDocument('a');
      session.deleteDocument('b');
      await _flush();
      expect(bootstrap.history.canGoBack, isFalse);
      bootstrap.history.goBack();
      expect(
        bootstrap.router.routeInformationProvider.value.uri.path,
        '/tasks',
      );
    },
  );

  test('history is bounded and disposal detaches both observers', () async {
    final bootstrap = await _bootstrap();
    addTearDown(bootstrap.disposeAsync);
    final history = WorkbenchNavigationHistory(
      router: bootstrap.router,
      workspace: bootstrap.session,
      maxEntries: 3,
    );
    bootstrap.router.go('/media');
    bootstrap.router.go('/tasks');
    bootstrap.router.go('/text');
    history.goBack();
    history.goBack();
    expect(history.current?.location.path, '/media');
    expect(history.canGoBack, isFalse);
    history.goForward();
    history.goForward();
    history.goForward();
    expect(history.current?.location.path, '/text');
    expect(history.canGoForward, isFalse);
    var notifications = 0;
    history.addListener(() => notifications++);
    final closing = history.disposeAsync();
    expect(history.disposeAsync(), same(closing));
    await closing;
    bootstrap.router.go('/tasks');
    bootstrap.session.createDocument();
    await _flush();
    history.goBack();
    history.goForward();
    expect(notifications, 0);
    expect(history.canGoBack, isFalse);
  });

  test(
    'earlier empty content and query locations replay without loops',
    () async {
      final bootstrap = await _bootstrap(const WorkspaceSnapshot());
      addTearDown(bootstrap.disposeAsync);
      final id = bootstrap.session.createDocument();
      await _flush();
      bootstrap.history.goBack();
      await _flush();
      expect(bootstrap.history.current?.resourceId, id);
      expect(bootstrap.history.canGoForward, isFalse);
      bootstrap.router.go('/text?mode=reading');
      bootstrap.router.go('/tasks');
      bootstrap.history.goBack();
      expect(
        bootstrap.router.routeInformationProvider.value.uri.query,
        'mode=reading',
      );
      bootstrap.router.go('/not-a-workbench-page');
      expect(bootstrap.history.current?.location.query, 'mode=reading');
    },
  );
}
