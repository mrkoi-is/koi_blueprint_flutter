import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:network_lab/features/network/domain/network_ports.dart';

Future<JSAny?> _request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    if (!result.isCompleted) result.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!result.isCompleted) {
      result.completeError(StateError('IndexedDB ${request.error?.name}'));
    }
  }).toJS;
  return result.future;
}

Future<void> _transaction(web.IDBTransaction transaction) {
  final result = Completer<void>();
  transaction.oncomplete = ((web.Event _) {
    if (!result.isCompleted) result.complete();
  }).toJS;
  transaction.onabort = ((web.Event _) {
    if (!result.isCompleted) {
      result.completeError(StateError('IndexedDB commit aborted'));
    }
  }).toJS;
  transaction.onerror = ((web.Event _) {}).toJS;
  return result.future;
}

Future<TransferStore> openTransferStore({
  String? nativeDirectory,
  String databaseName = 'koi_network_lab',
}) async {
  final released = Completer<JSAny?>();
  final acquired = Completer<void>();
  final ownership = web.window.navigator.locks
      .request(
        'network-transfer:$databaseName',
        web.LockOptions(mode: 'exclusive', ifAvailable: true),
        ((web.Lock? lock) {
          if (lock == null) {
            acquired.completeError(StateError('Transfer storage already open'));
            return Future<JSAny?>.value().toJS;
          }
          acquired.complete();
          return released.future.toJS;
        }).toJS,
      )
      .toDart;
  unawaited(
    ownership.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!acquired.isCompleted) acquired.completeError(error, stack);
      },
    ),
  );
  await acquired.future;
  try {
    final opening = web.window.indexedDB.open(databaseName, 1);
    opening.onupgradeneeded = ((web.Event _) {
      (opening.result as web.IDBDatabase).createObjectStore('records');
    }).toJS;
    final database = await _request(opening) as web.IDBDatabase;
    return IndexedTransferStore._(database, released, ownership);
  } catch (_) {
    released.complete();
    await ownership;
    rethrow;
  }
}

final class IndexedTransferStore implements TransferStore {
  IndexedTransferStore._(this._database, this._released, this._ownership);
  final web.IDBDatabase _database;
  final Completer<JSAny?> _released;
  final Future<JSAny?> _ownership;
  bool _closed = false;
  int _serial = 0;
  void _check(String id) {
    if (_closed) throw StateError('Transfer storage closed');
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid transfer ID');
    }
  }

  Future<Map<String, dynamic>?> _metadata(String key) async {
    final value = await _request(
      _database
          .transaction('records'.toJS, 'readonly')
          .objectStore('records')
          .get(key.toJS),
    );
    return value == null
        ? null
        : jsonDecode((value as JSString).toDart) as Map<String, dynamic>;
  }

  Future<void> _write(void Function(web.IDBObjectStore) write) async {
    final transaction = _database.transaction('records'.toJS, 'readwrite');
    final done = _transaction(transaction);
    try {
      write(transaction.objectStore('records'));
    } catch (_) {
      transaction.abort();
      await done.catchError((Object _) {});
      rethrow;
    }
    await done;
  }

  void _deleteChunks(web.IDBObjectStore store, Map<String, dynamic>? value) {
    if (value == null) return;
    for (var index = 0; index < (value['count'] as int); index++) {
      store.delete('${value['prefix']}/$index'.toJS);
    }
  }

  @override
  Future<TransferMetadata?> metadata(String id) async {
    _check(id);
    final value = await _metadata('stage/$id');
    return value == null ? null : TransferMetadata.fromJson(value);
  }

  @override
  Future<void> begin(String id, TransferMetadata metadata) async {
    _check(id);
    await discard(id);
    final value = {
      ...metadata.toJson(),
      'count': 0,
      'length': 0,
      'prefix': '$id/${DateTime.now().microsecondsSinceEpoch}-${_serial++}',
    };
    await _write((store) {
      store.put(jsonEncode(value).toJS, 'stage/$id'.toJS);
    });
  }

  @override
  Future<int> length(String id) async {
    _check(id);
    return (await _metadata('stage/$id'))?['length'] as int? ?? 0;
  }

  @override
  Future<void> append(String id, List<int> bytes) async {
    _check(id);
    final value = await _metadata('stage/$id');
    if (value == null) throw StateError('Transfer staging missing');
    final count = value['count'] as int;
    final updated = {
      ...value,
      'count': count + 1,
      'length': (value['length'] as int) + bytes.length,
    };
    await _write((store) {
      store.put(
        Uint8List.fromList(bytes).toJS,
        '${value['prefix']}/$count'.toJS,
      );
      store.put(jsonEncode(updated).toJS, 'stage/$id'.toJS);
    });
  }

  @override
  Stream<List<int>> read(String id) async* {
    _check(id);
    final value =
        await _metadata('stage/$id') ?? await _metadata('complete/$id');
    if (value == null) throw StateError('Transfer artifact missing');
    for (var index = 0; index < (value['count'] as int); index++) {
      final bytes = await _request(
        _database
            .transaction('records'.toJS, 'readonly')
            .objectStore('records')
            .get('${value['prefix']}/$index'.toJS),
      );
      if (bytes == null) throw StateError('Transfer chunk missing');
      yield (bytes as JSUint8Array).toDart;
    }
  }

  @override
  Future<void> commit(String id, String digest) async {
    _check(id);
    final value = await _metadata('stage/$id');
    if (value == null) throw StateError('Transfer staging missing');
    final previous = await _metadata('complete/$id');
    await _write((store) {
      _deleteChunks(store, previous);
      store.put(
        jsonEncode({...value, 'digest': digest}).toJS,
        'complete/$id'.toJS,
      );
      store.delete('stage/$id'.toJS);
    });
  }

  @override
  Future<void> discard(String id) async {
    _check(id);
    final value = await _metadata('stage/$id');
    await _write((store) {
      _deleteChunks(store, value);
      store.delete('stage/$id'.toJS);
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _database.close();
    _released.complete();
    await _ownership;
  }
}
