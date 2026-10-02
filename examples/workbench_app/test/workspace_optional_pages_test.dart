import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/document_selection_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/screens/bulk_documents_page.dart';
import 'package:workbench_app/features/workspace/presentation/screens/job_history_page.dart';
import 'package:workbench_app/l10n/app_strings.dart';

import 'presentation_support.dart';

const _documents = [
  WorkspaceDocument(id: 'a', title: 'Alpha', text: 'first body'),
  WorkspaceDocument(id: 'b', title: 'Beta', text: 'second body'),
  WorkspaceDocument(id: 'c', title: 'Gamma', text: 'third body'),
];

Future<(WorkspaceSession, MemoryRepository)> _open(
  WidgetTester tester,
  WorkspaceSnapshot snapshot,
  WidgetBuilder page,
) async {
  final repository = MemoryRepository(snapshot);
  final session = WorkspaceSession(
    repository: repository,
    assetStore: MemoryAssetStore(),
    fileImportPort: CancelImport(),
  );
  await session.initialize();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workspaceSessionProvider.overrideWithValue(session)],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session, repository);
}

Future<void> _close(WidgetTester tester, WorkspaceSession session) async {
  await tester.pumpWidget(const SizedBox());
  var closed = false;
  final closing = session.dispose().then((_) => closed = true);
  for (var i = 0; i < 30 && !closed; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(closed, isTrue);
  await closing;
  await tester.pump();
}

Future<void> _confirm(
  WidgetTester tester,
  String action, {
  bool accept = true,
}) async {
  await tester.tap(find.widgetWithText(TextButton, action));
  await tester.pumpAndSettle();
  await tester.tap(
    accept
        ? find.widgetWithText(FilledButton, action)
        : find.widgetWithText(TextButton, 'Cancel'),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bulk range selection survives filtering and confirms deletion', (
    tester,
  ) async {
    final (session, _) = await _open(
      tester,
      const WorkspaceSnapshot(documents: _documents),
      buildBulkDocumentsPage,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BulkDocumentsPage)),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alpha'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Gamma'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(container.read(documentSelectionProvider).ids, {'a', 'b', 'c'});
    expect(find.text('3 selected'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(container.read(documentSelectionProvider).ids, {'a', 'b', 'c'});
    await _confirm(tester, 'Delete selected', accept: false);
    expect(session.state.snapshot.documents, hasLength(3));
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(container.read(documentSelectionProvider).ids, isEmpty);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alpha'));
    await tester.pump();
    await _confirm(tester, 'Delete selected');
    expect(session.state.snapshot.documents.map((doc) => doc.id), ['b', 'c']);
    expect(container.read(documentSelectionProvider).ids, isEmpty);
    await _close(tester, session);
  });

  testWidgets('bulk drag preserves identities and removes deleted selections', (
    tester,
  ) async {
    final (session, _) = await _open(
      tester,
      const WorkspaceSnapshot(documents: _documents),
      buildBulkDocumentsPage,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BulkDocumentsPage)),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alpha'));
    await tester.pump();
    final handles = find.byIcon(Icons.drag_handle);
    final start = tester.getCenter(handles.first);
    final end = Offset(
      start.dx,
      tester.getBottomLeft(find.byType(ReorderableListView)).dy - 24,
    );
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.state.snapshot.documents.map((doc) => doc.id), [
      'b',
      'c',
      'a',
    ]);
    expect(container.read(documentSelectionProvider).ids, {'a'});
    expect(session.state.snapshot.documents.last.text, 'first body');

    // The provider is used by the page; external workspace changes must prune
    // the same selection even when rows disappear outside this page's actions.
    container.read(documentSelectionProvider.notifier).selectAll(['a', 'b']);
    session.deleteDocument('b');
    await tester.pumpAndSettle();
    expect(container.read(documentSelectionProvider).ids, {'a'});
    expect(find.text('Beta'), findsNothing);
    await _close(tester, session);
  });

  testWidgets(
    'history retries only the current attempt and retains old records',
    (tester) async {
      const previous = WorkspaceJob(
        id: 'import-1',
        kind: JobKind.importFiles,
        name: 'Import text',
        importKind: ImportKind.text,
        status: JobStatus.failed,
        error: 'first failure',
      );
      final current = previous.copyWith(
        currentAttempt: 2,
        error: 'second failure',
      );
      final (session, _) = await _open(
        tester,
        WorkspaceSnapshot(jobs: [current], jobHistory: [previous, current]),
        buildJobHistoryPage,
      );
      expect(find.byTooltip('Retry'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('import-1:1')),
          matching: find.byTooltip('Retry'),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Retry'));
      await tester.pumpAndSettle();
      expect(session.state.snapshot.jobs.single.id, 'import-1');
      expect(session.state.snapshot.jobs.single.currentAttempt, 3);
      expect(session.state.snapshot.jobs.single.status, JobStatus.cancelled);
      expect(
        session.state.snapshot.jobHistory.map((job) => job.currentAttempt),
        [1, 2, 3],
      );
      expect(find.textContaining('first failure'), findsOneWidget);
      await _close(tester, session);
    },
  );

  testWidgets(
    'history pages older attempts, filters, and keeps current tasks',
    (tester) async {
      final records = List.generate(
        35,
        (i) => WorkspaceJob(
          id: 'task-$i',
          kind: JobKind.importFiles,
          name: 'History ${i.toString().padLeft(2, '0')}',
          status: JobStatus.succeeded,
        ),
      );
      final (session, repository) = await _open(
        tester,
        WorkspaceSnapshot(jobs: [records.last], jobHistory: records),
        buildJobHistoryPage,
      );
      await tester.scrollUntilVisible(
        find.text('Load older records'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Load older records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load older records'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('History 00'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('History 00'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'history 34');
      await tester.pumpAndSettle();
      expect(find.text('History 34'), findsOneWidget);
      expect(find.text('History 00'), findsNothing);
      await _confirm(tester, 'Clear history', accept: false);
      expect(session.state.snapshot.jobHistory, hasLength(35));

      repository.failSave = true;
      await _confirm(tester, 'Clear history');
      expect(find.textContaining('write failure'), findsOneWidget);
      expect(repository.snapshot.jobHistory, hasLength(35));
      expect(session.state.snapshot.jobs, [records.last]);
      repository.failSave = false;
      final result = await session.save();
      expect(result.succeeded, isTrue);
      expect(repository.snapshot.jobHistory, isEmpty);
      expect(repository.snapshot.jobs, [records.last]);
      expect(find.text('No previous attempts'), findsOneWidget);
      await _close(tester, session);
    },
  );
}
