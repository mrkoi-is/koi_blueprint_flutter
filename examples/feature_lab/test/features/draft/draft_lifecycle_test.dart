import 'dart:async';

import 'package:feature_lab/features/draft/draft.dart';
import 'package:feature_lab/features/draft/draft_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:riverpod_annotation/experimental/scope.dart';

class _DraftRepository implements DraftRepository {
  _DraftRepository(this.content, {this.delaySaves = false});

  String content;
  final bool delaySaves;
  final List<String> savedTexts = [];
  final List<Completer<Result<void>>> pendingSaves = [];

  @override
  FutureResult<String> read() async => success(content);

  @override
  FutureResult<void> save(String text) async {
    savedTexts.add(text);
    if (delaySaves) {
      final pending = Completer<Result<void>>();
      pendingSaves.add(pending);
      final result = await pending.future;
      if (result.isRight()) content = text;
      return result;
    }
    content = text;
    return success(null);
  }
}

class _DraftSubmission implements DraftSubmission {
  @override
  FutureResult<void> submit(String text) async => success(null);
}

Finder _field(String editorId) => find.descendant(
  of: find.byKey(ValueKey(editorId)),
  matching: find.byType(TextFormField),
);

Finder _save(String editorId) => find.descendant(
  of: find.byKey(ValueKey(editorId)),
  matching: find.widgetWithText(FilledButton, 'Save'),
);

String _text(WidgetTester tester, String editorId) =>
    tester.widget<TextFormField>(_field(editorId)).controller!.text;

@Dependencies([DraftController])
void main() {
  test(
    'nested session owns drafts and a new session starts from its repository',
    () async {
      final root = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          draftRepositoryProvider().overrideWithValue(_DraftRepository('root')),
          draftSubmissionProvider().overrideWithValue(_DraftSubmission()),
        ],
      );
      addTearDown(root.dispose);
      final provider = draftControllerProvider(editorId: 'editor');
      expect((await root.read(provider.future)).text, 'root');

      final first = ProviderContainer(
        retry: (_, _) => null,
        parent: root,
        overrides: draftSessionOverrides(
          repositories: {'default': _DraftRepository('first session')},
          submissions: {'default': _DraftSubmission()},
        ),
      );
      try {
        expect((await first.read(provider.future)).text, 'first session');
        first.read(provider.notifier).edit('unsaved first session');
        expect(root.read(provider).requireValue.text, 'root');
      } finally {
        first.dispose();
      }
      final second = ProviderContainer(
        retry: (_, _) => null,
        parent: root,
        overrides: draftSessionOverrides(
          repositories: {'default': _DraftRepository('second session')},
          submissions: {'default': _DraftSubmission()},
        ),
      );
      addTearDown(second.dispose);
      expect((await second.read(provider.future)).text, 'second session');
    },
  );

  test(
    'save finishing after session disposal cannot update the next session',
    () async {
      final root = ProviderContainer(retry: (_, _) => null);
      addTearDown(root.dispose);
      final oldRepository = _DraftRepository('old session', delaySaves: true);
      final first = ProviderContainer(
        retry: (_, _) => null,
        parent: root,
        overrides: draftSessionOverrides(
          repositories: {'default': oldRepository},
          submissions: {'default': _DraftSubmission()},
        ),
      );
      final provider = draftControllerProvider(editorId: 'editor');
      await first.read(provider.future);
      final controller = first.read(provider.notifier)..edit('saving old edit');
      final saving = controller.save();
      first.dispose();

      final second = ProviderContainer(
        retry: (_, _) => null,
        parent: root,
        overrides: draftSessionOverrides(
          repositories: {'default': _DraftRepository('new session')},
          submissions: {'default': _DraftSubmission()},
        ),
      );
      addTearDown(second.dispose);
      expect((await second.read(provider.future)).text, 'new session');
      second.read(provider.notifier).edit('new session edit');
      oldRepository.pendingSaves.single.complete(
        failure(const AppFailure.unknown(message: 'late old error')),
      );
      await saving;
      expect(second.read(provider).requireValue.text, 'new session edit');
      expect(second.read(provider).requireValue.operationFailure, isNull);
    },
  );

  testWidgets(
    'two pages isolate editing, save payload, busy state and failure',
    (tester) async {
      final repository = _DraftRepository('initial', delaySaves: true);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          child: ProviderScope(
            retry: (_, _) => null,
            overrides: draftSessionOverrides(
              repositories: {'shared': repository},
              submissions: {'shared': _DraftSubmission()},
            ),
            child: const MaterialApp(
              home: Row(
                children: [
                  Expanded(
                    child: DraftPage(
                      key: ValueKey('one'),
                      draftId: 'shared',
                      editorId: 'one',
                    ),
                  ),
                  Expanded(
                    child: DraftPage(
                      key: ValueKey('two'),
                      draftId: 'shared',
                      editorId: 'two',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field('one'), 'first edit');
      await tester.enterText(_field('two'), 'second edit');
      await tester.pump();
      expect(_text(tester, 'one'), 'first edit');
      expect(_text(tester, 'two'), 'second edit');

      await tester.tap(_save('one'));
      await tester.pump();
      expect(repository.savedTexts, ['first edit']);
      expect(tester.widget<FilledButton>(_save('one')).onPressed, isNull);
      expect(tester.widget<FilledButton>(_save('two')).onPressed, isNotNull);
      await tester.tap(_save('two'));
      await tester.pump();
      expect(repository.savedTexts, ['first edit', 'second edit']);
      repository.pendingSaves[0].complete(
        failure(const AppFailure.unknown(message: 'first save failed')),
      );
      repository.pendingSaves[1].complete(success(null));
      await tester.pumpAndSettle();
      expect(_text(tester, 'one'), 'first edit');
      expect(_text(tester, 'two'), 'second edit');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('one')),
          matching: find.text('Draft operation failed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('two')),
          matching: find.text('Draft operation failed'),
        ),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(_save('one')).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(_save('two')).onPressed, isNotNull);
    },
  );

  testWidgets(
    'push and pop restore each editor, replacing session resets drafts',
    (tester) async {
      final rootRepository = _DraftRepository('app root');
      final firstRepository = _DraftRepository('first session');
      final firstNavigator = GlobalKey<NavigatorState>();

      @Dependencies([DraftController])
      Widget session(
        String id,
        _DraftRepository repository,
        GlobalKey<NavigatorState> navigator,
      ) => ProviderScope(
        retry: (_, _) => null,
        overrides: [
          draftRepositoryProvider().overrideWithValue(rootRepository),
          draftSubmissionProvider().overrideWithValue(_DraftSubmission()),
        ],
        child: ProviderScope(
          retry: (_, _) => null,
          key: ValueKey(id),
          overrides: draftSessionOverrides(
            repositories: {'default': repository},
            submissions: {'default': _DraftSubmission()},
          ),
          child: MaterialApp(
            navigatorKey: navigator,
            home: const DraftPage(key: ValueKey('one'), editorId: 'one'),
          ),
        ),
      );

      await tester.pumpWidget(
        session('first', firstRepository, firstNavigator),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'one'), 'first session');
      await tester.enterText(_field('one'), 'first route edit');
      unawaited(
        firstNavigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const DraftPage(key: ValueKey('two'), editorId: 'two'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'two'), 'first session');
      await tester.enterText(_field('two'), 'second route edit');
      await tester.tap(_save('two'));
      await tester.pumpAndSettle();
      expect(firstRepository.savedTexts, ['second route edit']);
      firstNavigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_text(tester, 'one'), 'first route edit');
      await tester.tap(_save('one'));
      await tester.pumpAndSettle();
      expect(firstRepository.savedTexts, [
        'second route edit',
        'first route edit',
      ]);

      // The popped page is reconstructed, while this session still owns its draft.
      unawaited(
        firstNavigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const DraftPage(key: ValueKey('two'), editorId: 'two'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'two'), 'second route edit');
      firstNavigator.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        session(
          'second',
          _DraftRepository('new session'),
          GlobalKey<NavigatorState>(),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'one'), 'new session');
      expect(rootRepository.savedTexts, isEmpty);
      expect(rootRepository.content, 'app root');
    },
  );
}
