import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';
import 'package:workbench_app/features/workspace/data/workspace_snapshot_codec.dart';

Future<WorkspaceStorage> openStorage({
  String? nativeDirectory,
  String webDatabaseName = 'koi_workbench',
}) async {
  final directory =
      nativeDirectory ??
      '${(await getApplicationSupportDirectory()).path}/workbench';
  final storage = NativeWorkspaceStorage(directory);
  await storage.initialize();
  return storage;
}

/// Each instance owns one directory and serializes snapshot transactions.
final class NativeWorkspaceStorage
    implements WorkspaceStorage, WorkspaceRepository, AssetStore {
  NativeWorkspaceStorage(String directory, {this.beforeSnapshotCommit})
    : _root = Directory(directory);

  /// Optional transaction fault injection, also useful for host IO coordination.
  final FutureOr<void> Function()? beforeSnapshotCommit;
  static const _codec = WorkspaceSnapshotCodec();
  final Directory _root;
  Future<void> _pending = Future.value();
  bool _closed = false;
  int _nextId = 0;
  final _operations = StorageOperations();
  static final Set<String> _owners = {};
  String? _ownerPath;
  RandomAccessFile? _lock;
  Future<void>? _closing;
  int _persistedVersion = 0;
  @override
  int get persistedVersion => _persistedVersion;
  @override
  WorkspaceRepository get repository => this;
  @override
  AssetStore get assetStore => this;
  @override
  String? get warning => _warning;
  String? _warning;
  String get _snapshotPath => '${_root.path}/workspace.json';
  Directory get _assets => Directory('${_root.path}/assets');
  Directory get _staging => Directory('${_root.path}/staging');

  Future<void> initialize() async {
    if (_closed || _closing != null) {
      throw const WorkspaceStorageException('已关闭的存储实例不能重新打开');
    }
    if (_lock != null) return;
    await _root.create(recursive: true);
    final ownerPath = await _root.resolveSymbolicLinks();
    // POSIX locks are process-scoped. Reject a duplicate in this owning isolate
    // before opening another descriptor (closing it would release POSIX locks).
    if (!_owners.add(ownerPath)) throw const WorkspaceInUse();
    RandomAccessFile? handle;
    try {
      handle = await File('$ownerPath/workspace.lock')
          .open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive, 0, 1);
      } on FileSystemException {
        throw const WorkspaceInUse();
      }
      _lock = handle;
      _ownerPath = ownerPath;
      await _assets.create(recursive: true);
      await _staging.create(recursive: true);
    } catch (error) {
      _lock = null;
      _ownerPath = null;
      try {
        await handle?.close();
      } finally {
        _owners.remove(ownerPath);
      }
      rethrow;
    }
  }

  void _checkOpen() {
    if (_closed || _lock == null) {
      throw const WorkspaceStorageException('工作区存储未打开或已关闭');
    }
  }

  File _asset(String key) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9]+)?$').hasMatch(key)) {
      throw const WorkspaceStorageException('无效素材键');
    }
    return File('${_assets.path}/$key');
  }

  File _staged(String key) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9]+)?$').hasMatch(key)) {
      throw const WorkspaceStorageException('无效暂存键');
    }
    return File('${_staging.path}/$key');
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<WorkspaceSnapshot> load() => _operations.run(() => _serialize(_load));
  Future<WorkspaceSnapshot> _load() async {
    _checkOpen();
    final current = File(_snapshotPath);
    final backup = File('$_snapshotPath.backup');
    DecodedWorkspaceSnapshot? loaded;
    if (await current.exists()) {
      try {
        final contents = await current.readAsString();
        loaded = _codec.decode(contents);
      } catch (error) {
        if (error is UnsupportedWorkspaceVersion) rethrow;
        if (!await backup.exists()) rethrow;
        final contents = await backup.readAsString();
        loaded = _codec.decode(contents);
        final preserved =
            '$_snapshotPath.corrupt_${DateTime.now().microsecondsSinceEpoch}';
        await current.rename(preserved);
        await backup.copy(_snapshotPath);
        _warning =
            '快照损坏，已恢复备份版本 ${loaded.snapshot.revision}；损坏内容保存在 $preserved';
      }
    } else if (await backup.exists()) {
      final contents = await backup.readAsString();
      loaded = _codec.decode(contents);
      await backup.copy(_snapshotPath);
      _warning = '上次保存中断，已恢复备份版本 ${loaded.snapshot.revision}';
    }
    if (loaded == null) {
      _persistedVersion = 0;
      return const WorkspaceSnapshot();
    }
    // Migration commit is outside recovery's catch: a failed upgrade must not
    // silently substitute an older backup or expose an editable unsaved model.
    _persistedVersion = loaded.storageVersion;
    if (loaded.needsMigration) {
      await _writeSnapshot(loaded.snapshot, loaded.storageVersion);
    }
    return loaded.snapshot;
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot, {int? expectedVersion}) =>
      _operations.run(
        () => _serialize(() => _writeSnapshot(snapshot, expectedVersion)),
      );
  Future<void> _writeSnapshot(
    WorkspaceSnapshot snapshot,
    int? expectedVersion,
  ) async {
    _checkOpen();
    final pending = File('$_snapshotPath.pending');
    final current = File(_snapshotPath);
    final backup = File('$_snapshotPath.backup');
    final contents = await current.exists()
        ? await current.readAsString()
        : null;
    final actual = contents == null
        ? 0
        : _codec.decode(contents).storageVersion;
    if (actual != (expectedVersion ?? persistedVersion)) {
      throw const WorkspaceConflict();
    }
    final nextVersion = actual + 1;
    await pending.writeAsString(
      _codec.encode(snapshot, storageVersion: nextVersion),
      flush: true,
    );
    await beforeSnapshotCommit?.call();
    final latest = await current.exists() ? await current.readAsString() : null;
    if (latest != contents) throw const WorkspaceConflict();
    if (contents != null) {
      // Copy before replacement so interruption retains a valid prior version.
      _codec.decode(await current.readAsString());
      await current.copy(backup.path);
    }
    try {
      if (Platform.isWindows && await current.exists()) {
        await current.delete();
      }
      await pending.rename(current.path);
      _persistedVersion = nextVersion;
    } catch (_) {
      if (!await current.exists() && await backup.exists()) {
        await backup.copy(current.path);
      }
      rethrow;
    }
  }

  @override
  Future<String> stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  }) => _operations.run(() => _stage(bytes, name: name, onBytes: onBytes));
  Future<String> _stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  }) async {
    _checkOpen();
    final suffix = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : 'bin';
    final extension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(suffix)
        ? suffix
        : 'bin';
    final key =
        'asset_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}.$extension';
    final file = _staged(key);
    final handle = await file.open(mode: FileMode.write);
    var count = 0;
    try {
      await for (final chunk in bytes) {
        _checkOpen();
        await handle.writeFrom(chunk);
        count += chunk.length;
        onBytes?.call(count);
      }
      await handle.flush();
      await handle.close();
      return key;
    } catch (_) {
      await handle.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<String> commit(String stagedKey) =>
      _operations.run(() => _commit(stagedKey));
  Future<String> _commit(String stagedKey) async {
    _checkOpen();
    await _staged(stagedKey).rename(_asset(stagedKey).path);
    return stagedKey;
  }

  @override
  Future<void> abort(String stagedKey) =>
      _operations.run(() => _abort(stagedKey));
  Future<void> _abort(String stagedKey) async {
    _checkOpen();
    final file = _staged(stagedKey);
    if (await file.exists()) await file.delete();
  }

  @override
  Stream<List<int>> read(String key) {
    _checkOpen();
    return _asset(key).openRead();
  }

  @override
  Future<Uint8List> readBytes(String key) =>
      _operations.run(() => _readBytes(key));
  Future<Uint8List> _readBytes(String key) async {
    _checkOpen();
    return _asset(key).readAsBytes();
  }

  @override
  Future<void> remove(String key) => _operations.run(() => _remove(key));
  Future<void> _remove(String key) async {
    _checkOpen();
    final file = _asset(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> cleanupStaging() => _operations.run(() => _cleanupStaging());
  Future<void> _cleanupStaging() async {
    _checkOpen();
    await for (final entry in _staging.list()) {
      await entry.delete(recursive: true);
    }
    final pending = File('$_snapshotPath.pending');
    if (await pending.exists()) await pending.delete();
  }

  @override
  Future<AssetPreviewLease> openPreview(String key) =>
      _operations.run(() => _openPreview(key));
  Future<AssetPreviewLease> _openPreview(String key) async {
    _checkOpen();
    final file = _asset(key);
    if (!await file.exists()) throw const WorkspaceStorageException('素材文件不存在');
    return _NativeLease(file.uri.toString());
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _operations.drain();
    await _pending;
    _closed = true;
    final handle = _lock;
    _lock = null;
    try {
      if (handle != null) {
        try {
          await handle.unlock(0, 1);
        } finally {
          await handle.close();
        }
      }
    } finally {
      _owners.remove(_ownerPath);
      _ownerPath = null;
    }
  }
}

final class _NativeLease implements AssetPreviewLease {
  const _NativeLease(this.uri);
  @override
  final String uri;
  @override
  Future<void> dispose() async {}
}
