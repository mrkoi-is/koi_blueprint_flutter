import 'dart:async';
import 'dart:io';

import 'package:feature_lab/features/draft/draft.dart';
import 'package:feature_lab/features/draft/data/file_draft_repository_stub.dart'
    as web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

class Submission implements DraftSubmission {
  bool fail = true;
  @override
  FutureResult<void> submit(String text) async => fail
      ? failure(const AppFailure.network(message: 'offline'))
      : success(null);
}

class BrokenRepository implements DraftRepository {
  @override
  FutureResult<String> read() async =>
      failure(const AppFailure.unknown(message: 'read failed'));
  @override
  FutureResult<void> save(String text) async =>
      failure(const AppFailure.unknown(message: 'save failed'));
}

class DelayedRepository implements DraftRepository {
  final pending = Completer<Result<void>>();
  @override
  FutureResult<String> read() async => success('initial');
  @override
  FutureResult<void> save(String text) => pending.future;
}

class MemoryRepository implements DraftRepository {
  String content = 'initial';
  @override
  FutureResult<String> read() async => success(content);
  @override
  FutureResult<void> save(String text) async => success(null);
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blueprint-draft-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('serialized writes survive repository restart; failures preserve existing file', () async {
    final path = '${directory.path}/nested/draft.txt';
    final repository = FileDraftRepository(path);
    expect((await repository.read()).getOrElse((_) => 'bad'), '');
    await Future.wait([repository.save('first'), repository.save('last')]);
    expect(
      (await FileDraftRepository(path).read()).getOrElse((_) => 'bad'),
      'last',
    );
    final impossible = FileDraftRepository('$path/child');
    expect((await impossible.save('lost')).isLeft(), isTrue);
    await File('${directory.path}/invalid').writeAsBytes([255]);
    expect(
      (await FileDraftRepository('${directory.path}/invalid').read()).isLeft(),
      isTrue,
    );
    expect(
      (await FileDraftRepository(path).read()).getOrElse((_) => 'bad'),
      'last',
    );
    expect((await web.FileDraftRepository(path).read()).isLeft(), isTrue);
    expect((await web.FileDraftRepository(path).save('x')).isLeft(), isTrue);
  });

  test('submission failure retains edits and disk drafts reopen', () async {
    final repository = FileDraftRepository('${directory.path}/draft.txt');
    final submission = Submission();
    final container = ProviderContainer(
      overrides: [
        draftRepositoryProvider.overrideWithValue(repository),
        draftSubmissionProvider.overrideWithValue(submission),
      ],
    );
    addTearDown(container.dispose);
    await container.read(draftControllerProvider.future);
    final controller = container.read(draftControllerProvider.notifier);
    controller.edit('my draft');
    await controller.save();
    await controller.submit();
    expect(
      container.read(draftControllerProvider).requireValue.operationFailure,
      isNotNull,
    );
    expect(
      container.read(draftControllerProvider).requireValue.text,
      'my draft',
    );
    submission.fail = false;
    await controller.submit();
    expect(
      container.read(draftControllerProvider).requireValue.operationFailure,
      isNull,
    );
    container.invalidate(draftControllerProvider);
    expect(
      (await container.read(draftControllerProvider.future)).text,
      'my draft',
    );
  });

  test('late save result cannot overwrite a newer edit', () async {
    final repository = DelayedRepository();
    final container = ProviderContainer(
      overrides: [draftRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(draftControllerProvider.future);
    final controller = container.read(draftControllerProvider.notifier);
    final saving = controller.save();
    controller.edit('new edit');
    repository.pending.complete(
      failure(const AppFailure.unknown(message: 'old error')),
    );
    await saving;
    expect(
      container.read(draftControllerProvider).requireValue.text,
      'new edit',
    );
    expect(
      container.read(draftControllerProvider).requireValue.operationFailure,
      isNull,
    );
  });

  testWidgets('editor keeps content and shows save/read errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          draftRepositoryProvider.overrideWithValue(BrokenRepository()),
        ],
        child: const MaterialApp(home: DraftPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Draft operation failed'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DraftPage)),
    );
    container.read(draftControllerProvider.notifier).edit('pending');
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'edited');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('Draft operation failed'), findsOneWidget);
  });

  testWidgets('external draft edit updates the mounted text field', (
    tester,
  ) async {
    final repository = MemoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [draftRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: DraftPage()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DraftPage)),
    );
    container.read(draftControllerProvider.notifier).edit('replacement');
    await tester.pump();
    expect(
      container.read(draftControllerProvider).requireValue.text,
      'replacement',
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'replacement',
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    controller.selection = const TextSelection.collapsed(offset: 3);
    container.read(draftControllerProvider.notifier).edit('replacement');
    await tester.pump();
    expect(controller.selection.extentOffset, 3);

    repository.content = 'reopened';
    container.invalidate(draftControllerProvider);
    await container.read(draftControllerProvider.future);
    await tester.pump();
    expect(controller.text, 'reopened');
  });
}
