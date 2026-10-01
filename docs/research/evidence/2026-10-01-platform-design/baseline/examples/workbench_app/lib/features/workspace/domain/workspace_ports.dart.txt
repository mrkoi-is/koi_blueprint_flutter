import 'dart:typed_data';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

abstract interface class WorkspaceRepository {
  Future<WorkspaceSnapshot> load();
  Future<void> save(WorkspaceSnapshot snapshot);
}

/// Application-owned content. Keys are opaque, never caller supplied paths.
abstract interface class AssetStore {
  Future<String> stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  });
  Future<String> commit(String stagedKey);
  Future<void> abort(String stagedKey);
  Stream<List<int>> read(String key);
  Future<Uint8List> readBytes(String key);
  Future<void> remove(String key);
  Future<void> cleanupStaging();
}

abstract interface class ImportSource {
  String get name;
  int get byteLength;
  Stream<List<int>> openRead();
  Future<void> close();
}

sealed class FileImportResult {
  const FileImportResult();
}

final class FilesSelected extends FileImportResult {
  const FilesSelected(this.files);
  final List<ImportSource> files;
}

final class ImportCancelled extends FileImportResult {
  const ImportCancelled();
}

final class ImportUnavailable extends FileImportResult {
  const ImportUnavailable(this.message);
  final String message;
}

final class ImportFailed extends FileImportResult {
  const ImportFailed(this.message);
  final String message;
}

abstract interface class FileImportPort {
  Future<FileImportResult> select(ImportKind kind);
}

final class ImportLimits {
  const ImportLimits({
    this.text = 256 * 1024,
    this.image = 20 * 1024 * 1024,
    this.video = 100 * 1024 * 1024,
  });
  final int text;
  final int image;
  final int video;
}

class WorkspaceStorageException implements Exception {
  const WorkspaceStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}
