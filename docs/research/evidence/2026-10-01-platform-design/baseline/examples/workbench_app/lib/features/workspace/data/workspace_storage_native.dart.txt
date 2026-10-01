import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';

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
  NativeWorkspaceStorage(String directory) : _root = Directory(directory);
  final Directory _root;
  Future<void> _pending = Future.value();
  bool _closed = false;
  int _nextId = 0;
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
    await _assets.create(recursive: true);
    await _staging.create(recursive: true);
  }

  void _checkOpen() {
    if (_closed) throw const WorkspaceStorageException('工作区存储已关闭');
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

  WorkspaceSnapshot _decode(String contents) {
    try {
      final decoded = jsonDecode(contents) as Map<String, dynamic>;
      final snapshot = WorkspaceSnapshot.fromJson(decoded);
      if (snapshot.schemaVersion != 1) {
        throw const WorkspaceStorageException('无法读取此工作区版本');
      }
      return snapshot;
    } on WorkspaceStorageException {
      rethrow;
    } catch (error) {
      throw WorkspaceStorageException('工作区快照损坏：$error');
    }
  }

  @override
  Future<WorkspaceSnapshot> load() async {
    _checkOpen();
    await _pending;
    final current = File(_snapshotPath);
    final backup = File('$_snapshotPath.backup');
    if (await current.exists()) {
      try {
        return _decode(await current.readAsString());
      } catch (error) {
        if (error is WorkspaceStorageException &&
            error.message == '无法读取此工作区版本') {
          rethrow;
        }
        if (!await backup.exists()) rethrow;
        final recovered = _decode(await backup.readAsString());
        final preserved =
            '$_snapshotPath.corrupt_${DateTime.now().microsecondsSinceEpoch}';
        await current.rename(preserved);
        await backup.copy(_snapshotPath);
        _warning = '快照损坏，已恢复备份版本 ${recovered.revision}；损坏内容保存在 $preserved';
        return recovered;
      }
    }
    if (await backup.exists()) {
      final recovered = _decode(await backup.readAsString());
      await backup.copy(_snapshotPath);
      _warning = '上次保存中断，已恢复备份版本 ${recovered.revision}';
      return recovered;
    }
    return const WorkspaceSnapshot();
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot) {
    _checkOpen();
    final operation = _pending.then((_) async {
      final pending = File('$_snapshotPath.pending');
      final current = File(_snapshotPath);
      final backup = File('$_snapshotPath.backup');
      await pending.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      if (await current.exists()) {
        // Copy before replacement so interruption retains a valid prior version.
        _decode(await current.readAsString());
        await current.copy(backup.path);
      }
      try {
        if (Platform.isWindows && await current.exists()) {
          await current.delete();
        }
        await pending.rename(current.path);
      } catch (_) {
        if (!await current.exists() && await backup.exists()) {
          await backup.copy(current.path);
        }
        rethrow;
      }
    });
    _pending = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<String> stage(
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
  Future<String> commit(String stagedKey) async {
    _checkOpen();
    await _staged(stagedKey).rename(_asset(stagedKey).path);
    return stagedKey;
  }

  @override
  Future<void> abort(String stagedKey) async {
    final file = _staged(stagedKey);
    if (await file.exists()) await file.delete();
  }

  @override
  Stream<List<int>> read(String key) {
    _checkOpen();
    return _asset(key).openRead();
  }

  @override
  Future<Uint8List> readBytes(String key) async {
    _checkOpen();
    return _asset(key).readAsBytes();
  }

  @override
  Future<void> remove(String key) async {
    final file = _asset(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> cleanupStaging() async {
    _checkOpen();
    await for (final entry in _staging.list()) {
      await entry.delete(recursive: true);
    }
    final pending = File('$_snapshotPath.pending');
    if (await pending.exists()) await pending.delete();
  }

  @override
  Future<AssetPreviewLease> openPreview(String key) async {
    _checkOpen();
    final file = _asset(key);
    if (!await file.exists()) throw const WorkspaceStorageException('素材文件不存在');
    return _NativeLease(file.uri.toString());
  }

  @override
  Future<void> close() async {
    await _pending;
    _closed = true;
  }
}

final class _NativeLease implements AssetPreviewLease {
  const _NativeLease(this.uri);
  @override
  final String uri;
  @override
  Future<void> dispose() async {}
}
