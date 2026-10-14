/// UI/domain values never expose Drift rows, SQL or platform handles.
final class LibraryNote {
  const LibraryNote({
    required this.id,
    required this.title,
    required this.body,
    required this.tags,
    required this.archived,
  });
  final int id;
  final String title;
  final String body;
  final List<String> tags;
  final bool archived;
}

abstract interface class LibraryRepository {
  Stream<List<LibraryNote>> watch({String query = '', bool archived = false});
  Future<int> save({
    int? id,
    required String title,
    required String body,
    required List<String> tags,
  });
  Future<void> setArchived(int id, bool value);
}

final class DatabaseAvailability {
  const DatabaseAvailability({
    required this.mode,
    required this.persistent,
    required this.multiTabSafe,
  });
  final String mode;
  final bool persistent;
  final bool multiTabSafe;
}
