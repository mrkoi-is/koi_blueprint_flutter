import 'dart:async';

import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_providers.g.dart';

@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject the owned repository');

@riverpod
Stream<List<LibraryNote>> libraryNotes(
  Ref ref, {
  String query = '',
  bool archived = false,
}) => ref
    .watch(libraryRepositoryProvider)
    .watch(query: query, archived: archived);

@riverpod
class LibraryCommands extends _$LibraryCommands {
  @override
  FutureOr<void> build() {}

  Future<bool> save({
    int? id,
    required String title,
    required String body,
    required List<String> tags,
  }) => _perform(() async {
    await ref
        .read(libraryRepositoryProvider)
        .save(id: id, title: title, body: body, tags: tags);
  });

  Future<bool> archive(int id, bool value) => _perform(
    () => ref.read(libraryRepositoryProvider).setArchived(id, value),
  );

  Future<bool> _perform(Future<void> Function() action) async {
    if (state.isLoading) return false;
    final hold = ref.keepAlive();
    state = const AsyncLoading();
    try {
      await action();
      if (ref.mounted) state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return false;
    } finally {
      hold.close();
    }
  }
}
