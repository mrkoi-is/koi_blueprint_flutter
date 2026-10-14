import 'package:database_lab/features/library/data/library_database.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:drift/drift.dart';

final class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._database);
  final LibraryDatabase _database;

  @override
  Stream<List<LibraryNote>> watch({String query = '', bool archived = false}) {
    final d = _database.libraryDocuments;
    final links = _database.libraryDocumentTags;
    final tags = _database.libraryTags;
    final statement =
        _database.select(d).join([
            leftOuterJoin(links, links.documentId.equalsExp(d.id)),
            leftOuterJoin(tags, tags.id.equalsExp(links.tagId)),
          ])
          ..where(d.archived.equals(archived))
          ..orderBy([OrderingTerm.desc(d.id), OrderingTerm.asc(tags.name)]);
    if (query.trim().isNotEmpty) {
      // Variables are bound by Drift, including quotes and SQL metacharacters.
      statement.where(
        d.title.contains(query.trim()) | d.body.contains(query.trim()),
      );
    }
    return statement.watch().map((rows) {
      final documents = <int, LibraryDocument>{};
      final names = <int, List<String>>{};
      for (final row in rows) {
        final document = row.readTable(d);
        documents[document.id] = document;
        final tag = row.readTableOrNull(tags);
        if (tag != null) (names[document.id] ??= []).add(tag.name);
      }
      return List.unmodifiable(
        documents.values.map(
          (document) => LibraryNote(
            id: document.id,
            title: document.title,
            body: document.body,
            archived: document.archived,
            tags: List.unmodifiable(names[document.id] ?? const <String>[]),
          ),
        ),
      );
    });
  }

  @override
  Future<int> save({
    int? id,
    required String title,
    required String body,
    required List<String> tags,
  }) {
    final normalizedTitle = title.trim();
    final normalizedTags = tags
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedTitle.isEmpty || normalizedTitle.length > 200) {
      throw ArgumentError('标题需要 1–200 个字符');
    }
    if (normalizedTags.length > 20 ||
        normalizedTags.any((value) => value.length > 40)) {
      throw ArgumentError('最多 20 个标签，每个不超过 40 个字符');
    }
    return _database.transaction(() async {
      final d = _database.libraryDocuments;
      final int documentId;
      if (id == null) {
        documentId = await _database
            .into(d)
            .insert(
              LibraryDocumentsCompanion.insert(
                title: normalizedTitle,
                body: body,
              ),
            );
      } else {
        final changed =
            await (_database.update(
              d,
            )..where((row) => row.id.equals(id))).write(
              LibraryDocumentsCompanion(
                title: Value(normalizedTitle),
                body: Value(body),
              ),
            );
        if (changed == 0) throw StateError('资料已不存在');
        documentId = id;
      }
      final links = _database.libraryDocumentTags;
      await (_database.delete(
        links,
      )..where((row) => row.documentId.equals(documentId))).go();
      for (final name in normalizedTags) {
        await _database
            .into(_database.libraryTags)
            .insert(
              LibraryTagsCompanion.insert(name: name),
              mode: InsertMode.insertOrIgnore,
            );
        final tag = await (_database.select(
          _database.libraryTags,
        )..where((row) => row.name.equals(name))).getSingle();
        await _database
            .into(links)
            .insert(
              LibraryDocumentTagsCompanion.insert(
                documentId: documentId,
                tagId: tag.id,
              ),
            );
      }
      return documentId;
    });
  }

  @override
  Future<void> setArchived(int id, bool value) async {
    final changed =
        await (_database.update(_database.libraryDocuments)
              ..where((row) => row.id.equals(id)))
            .write(LibraryDocumentsCompanion(archived: Value(value)));
    if (changed == 0) throw StateError('资料已不存在');
  }
}
