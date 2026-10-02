import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/screens/text_page.dart';
import 'package:workbench_app/l10n/app_strings.dart';

import 'presentation_support.dart';

const nextKey = ValueKey('document-segment-next');
const previousKey = ValueKey('document-segment-previous');
TextField field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const ValueKey('editor-a')));

Future<(WorkspaceSession, MemoryRepository)> openDocument(
  WidgetTester tester,
  String text,
) async {
  final repository = MemoryRepository(
    WorkspaceSnapshot(
      documents: [
        WorkspaceDocument(id: 'a', title: 'Large document', text: text),
        const WorkspaceDocument(
          id: 'b',
          title: 'Other',
          text: 'Unrelated content',
        ),
      ],
      preferences: const WorkspacePreferences(selectedDocumentId: 'a'),
    ),
  );
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
        home: const Scaffold(body: TextPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session, repository);
}

Future<T> finish<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  T? value;
  Object? failure;
  future.then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (var i = 0; i < 30 && !done; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(failure, isNull);
  expect(done, isTrue, reason: 'The owned operation must finish');
  return value as T;
}

Future<void> closeDocument(
  WidgetTester tester,
  WorkspaceSession session,
) async {
  await tester.pumpWidget(const SizedBox());
  await finish(tester, session.dispose());
  await tester.pump();
}

void main() {
  testWidgets(
    '128 KB segments reconstruct the full Unicode document without splitting graphemes',
    (tester) async {
      const family = '👩‍👩‍👧‍👦';
      final original = '${'x' * 4095}${family}e\u0301\r\n${'文🦊' * 42000}';
      final (session, _) = await openDocument(tester, original);
      expect(field(tester).controller!.text.length, lessThan(8192));
      expect(field(tester).controller!.text.endsWith(family), isTrue);
      final parts = <String>[];
      while (true) {
        parts.add(field(tester).controller!.text);
        final next = tester.widget<OutlinedButton>(find.byKey(nextKey));
        if (next.onPressed == null) break;
        await tester.tap(find.byKey(nextKey));
        await tester.pumpAndSettle();
      }
      expect(parts.join(), original);
      expect(session.state.snapshot.documents.first.text, original);
      expect(session.state.snapshot.documents.first.dirty, isFalse);
      await closeDocument(tester, session);
    },
  );

  testWidgets(
    'edits in different segments survive failed save, document switching and exit',
    (tester) async {
      final original = 'x' * 128000;
      final (session, repository) = await openDocument(tester, original);
      final first = field(tester).controller!.text;
      final firstEdit = '$first第一段🦊';
      await tester.enterText(find.byKey(const ValueKey('editor-a')), firstEdit);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(nextKey));
      await tester.pumpAndSettle();
      final second = field(tester).controller!.text;
      final secondEdit = '第二段$second';
      await tester.enterText(
        find.byKey(const ValueKey('editor-a')),
        secondEdit,
      );
      await tester.pumpAndSettle();
      final expected = original
          .replaceRange(0, first.length, firstEdit)
          .replaceRange(
            firstEdit.length,
            firstEdit.length + second.length,
            secondEdit,
          );
      expect(session.state.snapshot.documents.first.text, expected);
      repository.failSave = true;
      final failed = await finish(tester, session.save());
      expect(failed.succeeded, isFalse);
      expect(session.state.snapshot.documents.first.dirty, isTrue);
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedDocumentId: 'b'),
      );
      await tester.pumpAndSettle();
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedDocumentId: 'a'),
      );
      await tester.pumpAndSettle();
      expect(field(tester).controller!.text.length, lessThan(8192));
      expect(session.state.snapshot.documents.first.text, expected);
      repository.failSave = false;
      expect(
        (await finish(tester, session.prepareToClose())).succeeded,
        isTrue,
      );
      expect(repository.snapshot.documents.first.text, expected);
      expect(repository.snapshot.documents.last.text, 'Unrelated content');
      await closeDocument(tester, session);
      final restored = WorkspaceSession(
        repository: repository,
        assetStore: MemoryAssetStore(),
        fileImportPort: CancelImport(),
      );
      await restored.initialize();
      expect(restored.state.snapshot.documents.first.text, expected);
      await finish(tester, restored.dispose());
    },
  );

  testWidgets(
    'IME composition stays in its segment and navigation waits for commit',
    (tester) async {
      final (session, _) = await openDocument(tester, 'a' * 128000);
      await tester.tap(find.byKey(nextKey));
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byKey(const ValueKey('editor-a')));
      final original = field(tester).controller!.text;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '拼音$original',
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      expect(
        field(tester).controller!.value.composing,
        const TextRange(start: 0, end: 2),
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(nextKey)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(previousKey)).onPressed,
        isNull,
      );
      expect(
        session.state.snapshot.documents.first.text,
        '${'a' * 4096}拼音${'a' * (128000 - 4096)}',
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '拼音$original',
          selection: const TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byKey(nextKey)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(nextKey));
      await tester.pumpAndSettle();
      expect(
        session.state.snapshot.documents.first.text.contains('拼音'),
        isTrue,
      );
      await closeDocument(tester, session);
    },
  );

  testWidgets(
    'large paste is kept in full and resegmented after composition ends',
    (tester) async {
      final (session, _) = await openDocument(tester, 'x' * 128000);
      final replacedLength = field(tester).controller!.text.length;
      final pasted = '${'🦊e\u0301' * 10000}paste-end';
      await tester.enterText(find.byKey(const ValueKey('editor-a')), pasted);
      await tester.pumpAndSettle();
      expect(
        session.state.snapshot.documents.first.text,
        '$pasted${'x' * (128000 - replacedLength)}',
      );
      expect(field(tester).controller!.text.length, lessThan(8192));
      await closeDocument(tester, session);
    },
  );
}
