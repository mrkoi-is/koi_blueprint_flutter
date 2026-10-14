import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:koi_core/koi_core.dart';
import 'package:web/web.dart' as web;

Future<JSAny?> request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError(request.error?.message ?? 'IndexedDB request failed'),
  )).toJS;
  return result.future;
}

Future<void> completed(web.IDBTransaction transaction) {
  final result = Completer<void>();
  transaction.oncomplete = ((web.Event _) => result.complete()).toJS;
  transaction.onabort = ((web.Event _) => result.completeError(
    StateError(transaction.error?.message ?? 'IndexedDB transaction aborted'),
  )).toJS;
  transaction.onerror = ((web.Event _) {}).toJS;
  return result.future;
}

Future<BoundedDiagnosticStore> openDiagnosticStore({
  String databaseName = 'koi-app-diagnostics',
}) async {
  final pending = web.window.indexedDB.open(databaseName, 1);
  pending.onupgradeneeded = ((web.IDBVersionChangeEvent _) {
    (pending.result as web.IDBDatabase).createObjectStore('logs');
  }).toJS;
  final database = await request(pending) as web.IDBDatabase;
  Future<List<DiagnosticEvent>> read() async {
    final transaction = database.transaction('logs'.toJS, 'readonly');
    final done = completed(transaction);
    final raw = await request(
      transaction.objectStore('logs').get('events'.toJS),
    );
    await done;
    if (raw == null) return [];
    return (jsonDecode((raw as JSString).toDart) as List)
        .map(
          (event) =>
              DiagnosticEvent.fromJson(Map<String, Object?>.from(event as Map)),
        )
        .toList();
  }

  final store = BoundedDiagnosticStore(
    persist: (events) async {
      final transaction = database.transaction('logs'.toJS, 'readwrite');
      final done = completed(transaction);
      transaction
          .objectStore('logs')
          .put(
            jsonEncode(events.map((e) => e.toJson()).toList()).toJS,
            'events'.toJS,
          );
      await done;
    },
  );
  try {
    store.restore(await read());
  } catch (error) {
    // Keep the damaged IndexedDB value for diagnosis and continue in memory.
    // Recording into `store` here would silently overwrite the original row.
    final fallback = BoundedDiagnosticStore();
    fallback.persistenceError = error;
    fallback.record(
      AppLogLevel.warning,
      'Previous diagnostic log could not be restored',
      error: error,
    );
    fallback.onClose = () async => database.close();
    return fallback;
  }
  // The database connection is owned with the store, not by any diagnostic page.
  store.onClose = () async => database.close();
  return store;
}

Future<String> exportDiagnostics(Stream<List<int>> bytes) async {
  final parts = <JSAny>[];
  await for (final chunk in bytes) {
    parts.add(Uint8List.fromList(chunk).toJS);
  }
  final blob = web.Blob(
    parts.toJS,
    web.BlobPropertyBag(type: 'application/x-ndjson'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'diagnostics.ndjson';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  return 'diagnostics.ndjson';
}
