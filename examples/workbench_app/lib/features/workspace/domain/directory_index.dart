/// Opaque key relative to an explicitly selected directory, never an absolute
/// filesystem path exposed to presentation.
final class DirectoryCandidate {
  const DirectoryCandidate({required this.key, required this.name});
  final String key;
  final String name;
}

final class DirectoryFingerprint {
  const DirectoryFingerprint({
    required this.byteLength,
    required this.modifiedAt,
  });
  final int byteLength;
  final DateTime modifiedAt;

  bool matches(DirectoryFingerprint other) =>
      byteLength == other.byteLength && modifiedAt == other.modifiedAt;
}

final class IndexedFile {
  const IndexedFile({
    required this.key,
    required this.name,
    required this.fingerprint,
    required this.fileType,
  });
  final String key;
  final String name;
  final DirectoryFingerprint fingerprint;
  final String fileType;
}

abstract interface class DirectoryIndexSource {
  Stream<DirectoryCandidate> enumerate();
  Future<DirectoryFingerprint> fingerprint(DirectoryCandidate candidate);
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  );
}

enum DirectoryIndexStatus { completed, cancelled, failed }

final class DirectoryIndexIssue {
  const DirectoryIndexIssue({this.key, required this.message});
  final String? key;
  final String message;
}

final class DirectoryIndexProgress {
  const DirectoryIndexProgress({
    required this.visited,
    required this.inspected,
    required this.reused,
    required this.failures,
  });
  final int visited;
  final int inspected;
  final int reused;
  final int failures;
}

final class DirectoryIndexResult {
  DirectoryIndexResult({
    required this.status,
    required Map<String, IndexedFile> entries,
    required List<DirectoryIndexIssue> issues,
    required this.progress,
  }) : entries = Map.unmodifiable(entries),
       issues = List.unmodifiable(issues);
  final DirectoryIndexStatus status;
  final Map<String, IndexedFile> entries;
  final List<DirectoryIndexIssue> issues;
  final DirectoryIndexProgress progress;
}
