import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

final _owners = <String>{};
Future<TransferStore> openTransferStore({
  String? nativeDirectory,
  String databaseName = 'koi_network_lab',
}) async {
  final directory = Directory(
    nativeDirectory ??
        '${(await getApplicationSupportDirectory()).path}/koi_network_lab',
  );
  await directory.create(recursive: true);
  final identity = await directory.resolveSymbolicLinks();
  if (!_owners.add(identity)) throw StateError('Transfer storage already open');
  RandomAccessFile? lock;
  try {
    lock = await File('$identity/.owner').open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    return FileTransferStore._(Directory(identity), lock);
  } catch (_) {
    await lock?.close();
    _owners.remove(identity);
    rethrow;
  }
}

final class FileTransferStore implements TransferStore {
  FileTransferStore._(this.directory, this._lock);
  final Directory directory;
  final RandomAccessFile _lock;
  bool _closed = false;
  File _file(String id, String extension) {
    if (_closed) throw StateError('Transfer storage closed');
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid transfer ID');
    }
    return File('${directory.path}/$id.$extension');
  }

  @override
  Future<TransferMetadata?> metadata(String id) async {
    final file = _file(id, 'json');
    if (!await file.exists()) return null;
    return TransferMetadata.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> begin(String id, TransferMetadata metadata) async {
    await discard(id);
    await _file(id, 'part').writeAsBytes(const [], flush: true);
    await _file(
      id,
      'json',
    ).writeAsString(jsonEncode(metadata.toJson()), flush: true);
  }

  @override
  Future<int> length(String id) async {
    final file = _file(id, 'part');
    return await file.exists() ? file.length() : 0;
  }

  @override
  Future<void> append(String id, List<int> bytes) async {
    if (!await _file(id, 'json').exists()) {
      throw StateError('Transfer staging missing');
    }
    await _file(
      id,
      'part',
    ).writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  @override
  Stream<List<int>> read(String id) async* {
    final staged = _file(id, 'part');
    yield* (await staged.exists() ? staged : _file(id, 'bin')).openRead();
  }

  @override
  Future<void> commit(String id, String digest) async {
    final stage = _file(id, 'part');
    final completed = _file(id, 'bin');
    final backup = _file(id, 'previous');
    if (await backup.exists()) await backup.delete();
    if (await completed.exists()) await completed.rename(backup.path);
    try {
      await stage.rename(completed.path);
      await _file(id, 'sha256').writeAsString(digest, flush: true);
    } catch (_) {
      if (await completed.exists()) await completed.delete();
      if (await backup.exists()) await backup.rename(completed.path);
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
    final metadataFile = _file(id, 'json');
    if (await metadataFile.exists()) await metadataFile.delete();
  }

  @override
  Future<void> discard(String id) async {
    for (final extension in ['part', 'json']) {
      final file = _file(id, extension);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _lock.unlock();
    } finally {
      await _lock.close();
      _owners.remove(directory.path);
    }
  }
}
