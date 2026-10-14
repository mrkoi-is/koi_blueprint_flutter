import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

import 'runtime_sandbox_types.dart';

Future<RuntimeSandbox> createSandbox() async =>
    _WebSandbox('koi_runtime_fixture_${DateTime.now().microsecondsSinceEpoch}');

class _WebSandbox implements RuntimeSandbox {
  const _WebSandbox(this.name);
  final String name;
  @override
  String get description => 'Web isolated IndexedDB + Blob';
  @override
  Future<WorkspaceStorage> open() =>
      openWorkspaceStorage(webDatabaseName: name);
  @override
  Future<void> verifyReleasedUri(String uri) async {
    var revoked = false;
    try {
      await web.window.fetch(uri.toJS).toDart;
    } catch (_) {
      revoked = true;
    }
    if (!revoked) throw StateError('Disposed preview Blob URL still readable');
  }

  @override
  Future<void> dispose() async {
    final request = web.window.indexedDB.deleteDatabase(name);
    final done = Completer<void>();
    request.onsuccess = ((web.Event event) => done.complete()).toJS;
    request.onerror = ((web.Event event) => done.completeError(
      StateError('Runtime IndexedDB cleanup failed: ${request.error?.message}'),
    )).toJS;
    request.onblocked = ((web.Event event) => done.completeError(
      StateError('Runtime IndexedDB cleanup blocked by an open connection'),
    )).toJS;
    await done.future;
  }
}
