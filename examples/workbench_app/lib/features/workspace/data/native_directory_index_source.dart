import 'dart:io';

import 'package:workbench_app/features/workspace/domain/directory_index.dart';

/// Read-only adapter. The caller chooses this root; no recursive symlink traversal.
final class NativeDirectoryIndexSource implements DirectoryIndexSource {
  NativeDirectoryIndexSource(String root) : _root = Directory(root).absolute;
  final Directory _root;

  @override
  Stream<DirectoryCandidate> enumerate() async* {
    final prefix = _root.path.endsWith(Platform.pathSeparator)
        ? _root.path
        : '${_root.path}${Platform.pathSeparator}';
    await for (final entry in _root.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final key = entry.path
          .substring(prefix.length)
          .replaceAll(Platform.pathSeparator, '/');
      yield DirectoryCandidate(key: key, name: key.split('/').last);
    }
  }

  File _file(String key) {
    if (key.isEmpty ||
        key.contains('\\') ||
        key.startsWith('/') ||
        key
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw ArgumentError.value(key, 'key', 'Invalid directory index key');
    }
    return File(
      '${_root.path}${Platform.pathSeparator}${key.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  @override
  Future<DirectoryFingerprint> fingerprint(DirectoryCandidate candidate) async {
    final file = _file(candidate.key);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('文件已移除或已变成链接', file.path);
    }
    final root = await _root.resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!resolved.startsWith(prefix)) {
      throw const FileSystemException('索引文件位于选定目录之外');
    }
    final stat = await file.stat();
    return DirectoryFingerprint(
      byteLength: stat.size,
      modifiedAt: stat.modified.toUtc(),
    );
  }

  @override
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  ) async => IndexedFile(
    key: candidate.key,
    name: candidate.name,
    fingerprint: fingerprint,
    fileType: candidate.name.contains('.')
        ? candidate.name.split('.').last.toLowerCase()
        : 'unknown',
  );
}
