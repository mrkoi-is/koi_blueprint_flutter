import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';

Future<WorkspaceStorage> openStorage({
  String? nativeDirectory,
  String webDatabaseName = 'koi_workbench',
}) async {
  final request = web.window.indexedDB.open(webDatabaseName, 1);
  request.onupgradeneeded = ((web.Event event) {
    final database = request.result as web.IDBDatabase;
    for (final name in ['metadata', 'assets', 'staging']) {
      if (!database.objectStoreNames.contains(name)) {
        database.createObjectStore(name);
      }
    }
  }).toJS;
  final database =
      await _request(request, openRequest: request) as web.IDBDatabase;
  return WebWorkspaceStorage(database);
}

Future<JSAny?> _request(
  web.IDBRequest request, {
  web.IDBOpenDBRequest? openRequest,
}) {
  final completed = Completer<JSAny?>();
  request.onsuccess = ((web.Event event) {
    if (!completed.isCompleted) {
      completed.complete(request.result);
    } else if (openRequest != null) {
      (request.result as web.IDBDatabase).close();
    }
  }).toJS;
  request.onerror = ((web.Event event) {
    if (!completed.isCompleted) {
      completed.completeError(
        WorkspaceStorageException(
          '浏览器存储请求失败：${request.error?.name}: ${request.error?.message}',
        ),
      );
    }
  }).toJS;
  if (openRequest != null) {
    openRequest.onblocked = ((web.Event event) {
      if (!completed.isCompleted) {
        completed.completeError(
          const WorkspaceStorageException('浏览器工作区升级被其他标签页阻塞，请关闭其他工作台后重试'),
        );
      }
    }).toJS;
  }
  return completed.future;
}

/// Success is the transaction completion event, never just request success.
Future<void> _transaction(web.IDBTransaction transaction) {
  final completed = Completer<void>();
  transaction.oncomplete = ((web.Event event) {
    if (!completed.isCompleted) completed.complete();
  }).toJS;
  transaction.onabort = ((web.Event event) {
    if (!completed.isCompleted) {
      completed.completeError(
        WorkspaceStorageException(
          '浏览器存储提交失败：${transaction.error?.name}: ${transaction.error?.message}',
        ),
      );
    }
  }).toJS;
  transaction.onerror = ((web.Event event) {
    // An error normally aborts the transaction. Only oncomplete is success.
  }).toJS;
  return completed.future;
}

final class WebWorkspaceStorage
    implements WorkspaceStorage, WorkspaceRepository, AssetStore {
  WebWorkspaceStorage(this._database);
  final web.IDBDatabase _database;
  Future<void> _pending = Future.value();
  bool _closed = false;
  int _nextId = 0;
  final Set<_WebLease> _leases = {};
  @override
  WorkspaceRepository get repository => this;
  @override
  AssetStore get assetStore => this;
  @override
  String? get warning => null;

  void _checkOpen() {
    if (_closed) throw const WorkspaceStorageException('浏览器工作区已关闭');
  }

  Future<JSAny?> _get(String store, String key) async {
    _checkOpen();
    final transaction = _database.transaction(store.toJS, 'readonly');
    final done = _transaction(transaction);
    final results = await Future.wait<Object?>([
      _request(transaction.objectStore(store).get(key.toJS)),
      done,
    ]);
    return results.first as JSAny?;
  }

  Future<void> _put(String store, String key, JSAny value) async {
    _checkOpen();
    final transaction = _database.transaction(store.toJS, 'readwrite');
    final done = _transaction(transaction);
    transaction.objectStore(store).put(value, key.toJS);
    await done;
  }

  Future<void> _delete(String store, String key) async {
    _checkOpen();
    final transaction = _database.transaction(store.toJS, 'readwrite');
    final done = _transaction(transaction);
    transaction.objectStore(store).delete(key.toJS);
    await done;
  }

  @override
  Future<WorkspaceSnapshot> load() async {
    await _pending;
    final result = await _get('metadata', 'workspace');
    if (result == null) return const WorkspaceSnapshot();
    try {
      final snapshot = WorkspaceSnapshot.fromJson(
        jsonDecode((result as JSString).toDart) as Map<String, dynamic>,
      );
      if (snapshot.schemaVersion != 1) {
        throw const WorkspaceStorageException('无法读取此浏览器工作区版本');
      }
      return snapshot;
    } on WorkspaceStorageException {
      rethrow;
    } catch (error) {
      throw WorkspaceStorageException('浏览器工作区快照损坏：$error');
    }
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot) {
    _checkOpen();
    final operation = _pending.then(
      (_) => _put('metadata', 'workspace', jsonEncode(snapshot.toJson()).toJS),
    );
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
    final parts = <JSAny>[];
    var count = 0;
    await for (final chunk in bytes) {
      _checkOpen();
      parts.add(Uint8List.fromList(chunk).toJS);
      count += chunk.length;
      onBytes?.call(count);
    }
    // File APIs on Web may buffer internally; this is not a zero-copy claim.
    final mime = name.toLowerCase().endsWith('.png')
        ? 'image/png'
        : name.toLowerCase().endsWith('.jpg') ||
              name.toLowerCase().endsWith('.jpeg')
        ? 'image/jpeg'
        : name.toLowerCase().endsWith('.mp4')
        ? 'video/mp4'
        : 'application/octet-stream';
    final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: mime));
    final key = 'asset_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';
    await _put('staging', key, blob);
    return key;
  }

  @override
  Future<String> commit(String stagedKey) async {
    final value = await _get('staging', stagedKey);
    if (value == null) throw const WorkspaceStorageException('浏览器暂存素材不存在');
    final transaction = _database.transaction(
      ['assets'.toJS, 'staging'.toJS].toJS,
      'readwrite',
    );
    final done = _transaction(transaction);
    transaction.objectStore('assets').put(value, stagedKey.toJS);
    transaction.objectStore('staging').delete(stagedKey.toJS);
    await done;
    return stagedKey;
  }

  @override
  Future<void> abort(String stagedKey) => _delete('staging', stagedKey);
  @override
  Stream<List<int>> read(String key) async* {
    yield await readBytes(key);
  }

  @override
  Future<Uint8List> readBytes(String key) async {
    final value = await _get('assets', key);
    if (value == null) throw const WorkspaceStorageException('浏览器素材不存在');
    return (await (value as web.Blob).arrayBuffer().toDart).toDart
        .asUint8List();
  }

  @override
  Future<void> remove(String key) => _delete('assets', key);
  @override
  Future<void> cleanupStaging() async {
    _checkOpen();
    final transaction = _database.transaction('staging'.toJS, 'readwrite');
    final done = _transaction(transaction);
    transaction.objectStore('staging').clear();
    await done;
  }

  @override
  Future<AssetPreviewLease> openPreview(String key) async {
    final value = await _get('assets', key);
    if (value == null) throw const WorkspaceStorageException('浏览器素材不存在');
    late final _WebLease lease;
    lease = _WebLease(
      web.URL.createObjectURL(value as web.Blob),
      () => _leases.remove(lease),
    );
    _leases.add(lease);
    return lease;
  }

  @override
  Future<void> close() async {
    await _pending;
    for (final lease in _leases.toList()) {
      await lease.dispose();
    }
    _closed = true;
    _database.close();
  }
}

final class _WebLease implements AssetPreviewLease {
  _WebLease(this.uri, this._onDispose);
  @override
  final String uri;
  final void Function() _onDispose;
  bool _disposed = false;
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    web.URL.revokeObjectURL(uri);
    _onDispose();
  }
}
