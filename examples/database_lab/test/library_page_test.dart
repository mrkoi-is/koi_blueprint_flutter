import 'dart:async';

import 'package:database_lab/app.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:database_lab/features/library/presentation/providers/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'create, validation, failure keeps input, retry and archive use repository',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
          child: const DatabaseLabApp(
            locale: Locale('zh'),
            availability: DatabaseAvailability(
              mode: 'test',
              persistent: true,
              multiTabSafe: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入标题'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '保留输入');
      await tester.enterText(fields.at(1), '正文');
      await tester.enterText(fields.at(2), '资料,中文');
      repository.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('保留输入'), findsOneWidget);
      expect(find.textContaining('内容仍保留'), findsOneWidget);
      repository.fail = false;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.notes.single.tags, ['资料', '中文']);
      await tester.tap(find.byTooltip('归档资料'));
      await tester.pumpAndSettle();
      expect(repository.notes.single.archived, isTrue);
      await tester.tap(find.widgetWithText(FilterChip, '已归档'));
      await tester.pumpAndSettle();
      expect(find.text('保留输入'), findsOneWidget);
      await tester.tap(find.byTooltip('恢复资料'));
      await tester.pumpAndSettle();
      expect(repository.notes.single.archived, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await repository.changes.close();
    },
  );

  testWidgets(
    'narrow view exposes nonpersistent mode without hiding new action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
          child: const DatabaseLabApp(
            locale: Locale('zh'),
            availability: DatabaseAvailability(
              mode: 'inMemory',
              persistent: false,
              multiTabSafe: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('仅提供临时存储'), findsOneWidget);
      expect(find.byTooltip('新建资料'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await repository.changes.close();
    },
  );
}

final class _Repository implements LibraryRepository {
  final changes = StreamController<void>.broadcast();
  final notes = <LibraryNote>[];
  bool fail = false;
  @override
  Stream<List<LibraryNote>> watch({
    String query = '',
    bool archived = false,
  }) async* {
    List<LibraryNote> current() => notes
        .where(
          (note) => note.archived == archived && note.title.contains(query),
        )
        .toList();
    yield current();
    await for (final _ in changes.stream) {
      yield current();
    }
  }

  @override
  Future<int> save({
    int? id,
    required String title,
    required String body,
    required List<String> tags,
  }) async {
    if (fail) throw StateError('disk is busy');
    notes.removeWhere((note) => note.id == id);
    notes.add(
      LibraryNote(
        id: id ?? 1,
        title: title,
        body: body,
        tags: tags,
        archived: false,
      ),
    );
    changes.add(null);
    return id ?? 1;
  }

  @override
  Future<void> setArchived(int id, bool value) async {
    final index = notes.indexWhere((note) => note.id == id);
    final note = notes[index];
    notes[index] = LibraryNote(
      id: note.id,
      title: note.title,
      body: note.body,
      tags: note.tags,
      archived: value,
    );
    changes.add(null);
  }
}
