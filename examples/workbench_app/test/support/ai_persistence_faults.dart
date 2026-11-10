import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
import 'package:workbench_app/core/window/workbench_exit_binding.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import '../presentation_support.dart';
import 'ai_persistence_sandbox.dart';

Future<UiPreferencesStore> _preferences() async {
  final preferences = MemoryUiPreferencesStore();
  await preferences.write({'density': 'compact', 'locale': 'zh'});
  return preferences;
}

/// Intercepts only writes; reads, versioning and ownership are real storage.
final class FaultStorage implements WorkspaceStorage {
  FaultStorage(this.actual) : repository = FaultRepository(actual.repository);
  final WorkspaceStorage actual;
  @override
  final FaultRepository repository;
  @override
  AssetStore get assetStore => actual.assetStore;
  @override
  String? get warning => actual.warning;
  @override
  Future<AssetPreviewLease> openPreview(String key) => actual.openPreview(key);
  @override
  Future<void> close() => actual.close();
}

final class FaultRepository implements WorkspaceRepository {
  FaultRepository(this.actual);
  final WorkspaceRepository actual;
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  int attempts = 0;
  @override
  int get persistedVersion => actual.persistedVersion;
  @override
  Future<WorkspaceSnapshot> load() => actual.load();
  @override
  Future<void> save(WorkspaceSnapshot snapshot, {int? expectedVersion}) async {
    attempts++;
    final signal = entered;
    if (signal != null && !signal.isCompleted) signal.complete();
    await gate?.future;
    if (fail) throw StateError('injected before durable write');
    await actual.save(snapshot, expectedVersion: expectedVersion);
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Timed out waiting for persistence operation');
}

Future<void> _save(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<AppExitResponse> _exit(WidgetTester tester) async {
  AppExitResponse? response;
  Object? failure;
  tester.binding.handleRequestAppExit().then<void>(
    (value) {
      response = value;
    },
    onError: (Object error) {
      failure = error;
    },
  );
  await _until(tester, () => response != null || failure != null);
  if (failure != null) throw StateError('Exit failed: $failure');
  return response!;
}

Future<({RuntimeSandbox sandbox, FaultStorage storage, WorkbenchBootstrap app})>
_mount(WidgetTester tester) async {
  final fixture = (await tester.runAsync(() async {
    final sandbox = await createRuntimeSandbox();
    final actual = await sandbox.open();
    await actual.repository.save(
      const WorkspaceSnapshot(
        documents: [WorkspaceDocument(id: 'doc', title: '原始资料', text: '初始内容')],
        preferences: WorkspacePreferences(selectedDocumentId: 'doc'),
      ),
    );
    final storage = FaultStorage(actual);
    final app = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      openPreferences: _preferences,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
      initialLocation: '/text',
    );
    return (sandbox: sandbox, storage: storage, app: app);
  }))!;
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(WorkbenchApp(bootstrap: fixture.app));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('editor-doc')), findsOneWidget);
  return fixture;
}

Future<void> _cleanup(
  WidgetTester tester,
  RuntimeSandbox sandbox,
  WorkbenchBootstrap app,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _disposeOwner(tester, app);
  await tester.runAsync(sandbox.dispose);
}

Future<void> _disposeOwner(WidgetTester tester, WorkbenchBootstrap app) async {
  var closed = false;
  Object? failure;
  app.disposeAsync().then(
    (_) => closed = true,
    onError: (Object error) {
      failure = error;
      closed = true;
    },
  );
  for (var i = 0; i < 300 && !closed; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(closed, isTrue, reason: 'All workspace owners must release');
  expect(failure, isNull);
}

Future<void> _reopenAndExpect(
  WidgetTester tester,
  RuntimeSandbox sandbox,
  WorkbenchBootstrap old,
  String text,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  WorkbenchBootstrap? next;
  try {
    await _disposeOwner(tester, old);
    next = (await tester.runAsync(
      () => WorkbenchBootstrap.create(
        openStorage: sandbox.open,
        openPreferences: _preferences,
        fileImportPort: CancelImport(),
        createPlayback: FakePlayback.new,
        initialLocation: '/text',
      ),
    ))!;
    await tester.pumpWidget(WorkbenchApp(bootstrap: next));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('editor-doc')))
          .controller!
          .text,
      text,
    );
  } finally {
    if (next != null) {
      await _cleanup(tester, sandbox, next);
    } else {
      await _cleanup(tester, sandbox, old);
    }
  }
}

void registerPersistenceFaultTests() {
  testWidgets(
    'W2 failed save preserves durable content; retry survives reopen',
    (tester) async {
      final f = await _mount(tester);
      var reopened = false;
      try {
        f.storage.repository.fail = true;
        await tester.enterText(
          find.byKey(const ValueKey('editor-doc')),
          '失败后草稿',
        );
        await _save(tester);
        await _until(tester, () => f.app.session.state.error != null);
        final disk = await tester.runAsync(f.storage.actual.repository.load);
        expect(disk!.documents.single.text, '初始内容');
        expect(f.app.session.state.snapshot.documents.single.dirty, isTrue);
        await tester.enterText(
          find.byKey(const ValueKey('editor-doc')),
          '重试后的内容',
        );
        f.storage.repository.fail = false;
        await _save(tester);
        await _until(
          tester,
          () => !f.app.session.state.snapshot.documents.single.dirty,
        );
        reopened = true;
        await _reopenAndExpect(tester, f.sandbox, f.app, '重试后的内容');
      } finally {
        if (!reopened) await _cleanup(tester, f.sandbox, f.app);
      }
    },
  );

  testWidgets('W3 save acknowledgement cannot clear edits made during write', (
    tester,
  ) async {
    final f = await _mount(tester);
    var reopened = false;
    try {
      f.storage.repository.gate = Completer<void>();
      f.storage.repository.entered = Completer<void>();
      await tester.enterText(find.byKey(const ValueKey('editor-doc')), '首版');
      await _save(tester);
      await _until(tester, () => f.storage.repository.entered!.isCompleted);
      await tester.enterText(
        find.byKey(const ValueKey('editor-doc')),
        '保存期间的新版',
      );
      f.storage.repository.gate!.complete();
      f.storage.repository.gate = null;
      await _until(tester, () => !f.app.session.state.saving);
      expect(f.app.session.state.snapshot.documents.single.dirty, isTrue);
      final disk = await tester.runAsync(f.storage.actual.repository.load);
      expect(disk!.documents.single.text, '首版');
      await _save(tester);
      await _until(
        tester,
        () => !f.app.session.state.snapshot.documents.single.dirty,
      );
      reopened = true;
      await _reopenAndExpect(tester, f.sandbox, f.app, '保存期间的新版');
    } finally {
      final gate = f.storage.repository.gate;
      if (gate != null && !gate.isCompleted) gate.complete();
      if (!reopened) await _cleanup(tester, f.sandbox, f.app);
    }
  });

  testWidgets('W4 failed close keeps real storage owned and editor usable', (
    tester,
  ) async {
    final f = await _mount(tester);
    try {
      expect(tester.binding, isA<WorkbenchExitBinding>());
      f.storage.repository.fail = true;
      await tester.enterText(
        find.byKey(const ValueKey('editor-doc')),
        '关闭失败草稿',
      );
      final response = await _exit(tester);
      expect(response, AppExitResponse.cancel);
      await tester.pump();
      expect(find.byKey(const ValueKey('editor-doc')), findsOneWidget);
      await tester.runAsync(() async {
        await expectLater(f.sandbox.open(), throwsA(isA<WorkspaceInUse>()));
      });
      await tester.enterText(
        find.byKey(const ValueKey('editor-doc')),
        '取消后继续编辑',
      );
      f.storage.repository.fail = false;
      expect(await _exit(tester), AppExitResponse.exit);
      final reopened = await tester.runAsync(f.sandbox.open);
      try {
        final disk = await tester.runAsync(reopened!.repository.load);
        expect(disk!.documents.single.text, '取消后继续编辑');
      } finally {
        await tester.runAsync(reopened!.close);
      }
    } finally {
      await _cleanup(tester, f.sandbox, f.app);
    }
  });

  testWidgets('W6 duplicate owner fails and fresh owner reads after release', (
    tester,
  ) async {
    final f = await _mount(tester);
    try {
      await tester.runAsync(() async {
        await expectLater(f.sandbox.open(), throwsA(isA<WorkspaceInUse>()));
        expect(
          (await f.storage.actual.repository.load()).documents.single.text,
          '初始内容',
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _disposeOwner(tester, f.app);
      final next = (await tester.runAsync(f.sandbox.open))!;
      try {
        final disk = await tester.runAsync(next.repository.load);
        expect(disk!.documents.single.text, '初始内容');
      } finally {
        await tester.runAsync(next.close);
      }
    } finally {
      await _cleanup(tester, f.sandbox, f.app);
    }
  });
}
