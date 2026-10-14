import 'dart:async';

import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_providers.g.dart';

@Riverpod(keepAlive: true, dependencies: [])
LibraryRepository libraryRepository(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject the owned repository');

@Riverpod(dependencies: [libraryRepository])
Stream<List<LibraryNote>> libraryNotes(
  Ref ref, {
  String query = '',
  bool archived = false,
}) => ref
    .watch(libraryRepositoryProvider)
    .watch(query: query, archived: archived);

@Riverpod(dependencies: [libraryRepository])
class LibraryCommands extends _$LibraryCommands {
  int _generation = 0;
  @override
  FutureOr<void> build() {
    ref.watch(libraryRepositoryProvider);
    ref.onDispose(() => _generation++);
  }

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
    final generation = ++_generation;
    final hold = ref.keepAlive();
    state = const AsyncLoading();
    try {
      await action();
      if (!ref.mounted || generation != _generation) return false;
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (!ref.mounted || generation != _generation) return false;
      state = AsyncError(error, stack);
      return false;
    } finally {
      hold.close();
    }
  }
}

@Riverpod(dependencies: [libraryRepository])
class LibraryFilter extends _$LibraryFilter {
  @override
  ({String query, bool archived}) build() {
    ref.watch(libraryRepositoryProvider);
    return (query: '', archived: false);
  }

  void setQuery(String value) =>
      state = (query: value, archived: state.archived);
  void setArchived(bool value) => state = (query: state.query, archived: value);
}

@Riverpod(dependencies: [LibraryCommands, libraryRepository])
class LibraryDraft extends _$LibraryDraft {
  int _generation = 0;
  late ({String title, String body, String tags}) _saved;
  int? _id;
  @override
  ({String title, String body, String tags, bool dirty}) build({
    int? id,
    String title = '',
    String body = '',
    String tags = '',
  }) {
    ref.watch(libraryRepositoryProvider);
    _id = id;
    _saved = (title: title, body: body, tags: tags);
    ref.onDispose(() => _generation++);
    return (title: title, body: body, tags: tags, dirty: false);
  }

  void update({String? title, String? body, String? tags}) {
    final values = (
      title: title ?? state.title,
      body: body ?? state.body,
      tags: tags ?? state.tags,
    );
    state = (
      title: values.title,
      body: values.body,
      tags: values.tags,
      dirty: values != _saved,
    );
  }

  Future<bool> save() async {
    final generation = ++_generation;
    final submitted = (title: state.title, body: state.body, tags: state.tags);
    final success = await ref
        .read(libraryCommandsProvider.notifier)
        .save(
          id: _id,
          title: submitted.title,
          body: submitted.body,
          tags: submitted.tags.split(RegExp('[,，]')),
        );
    if (!ref.mounted || generation != _generation) return false;
    if (success) {
      _saved = submitted;
      update();
    }
    return success;
  }
}
