import 'dart:async';

import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:database_lab/features/library/presentation/providers/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/experimental/scope.dart';

@Dependencies([LibraryDraft])
void main() {
  test('保存提交的版本，期间新编辑继续 dirty', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = libraryDraftProvider();
    container.listen(provider, (_, _) {});
    final draft = container.read(provider.notifier);
    draft.update(title: 'first');
    final saving = draft.save();
    draft.update(title: 'second');
    repository.gate.complete(1);
    expect(await saving, true);
    expect(repository.savedTitle, 'first');
    expect(container.read(provider).title, 'second');
    expect(container.read(provider).dirty, true);
  });
}

final class _Repository implements LibraryRepository {
  final gate = Completer<int>();
  String? savedTitle;
  @override
  Future<int> save({
    int? id,
    required String title,
    required String body,
    required List<String> tags,
  }) {
    savedTitle = title;
    return gate.future;
  }

  @override
  Stream<List<LibraryNote>> watch({String query = '', bool archived = false}) =>
      const Stream.empty();
  @override
  Future<void> setArchived(int id, bool value) async {}
}
