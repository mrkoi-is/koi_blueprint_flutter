import 'dart:async';

import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Platform-specific source kept outside the pure domain contract.
abstract interface class AssetPreviewLease {
  String get uri;
  Future<void> dispose();
}

abstract interface class WorkspaceStorage {
  WorkspaceRepository get repository;
  AssetStore get assetStore;
  String? get warning;
  Future<AssetPreviewLease> openPreview(String key);
  Future<void> close();
}

/// Closing rejects new IO and waits for operations already accepted.
final class StorageOperations {
  final Set<Future<void>> _pending = {};
  bool _closing = false;
  Future<T> run<T>(Future<T> Function() operation) {
    if (_closing) {
      return Future.error(const WorkspaceStorageException('工作区正在关闭'));
    }
    final done = Completer<void>();
    _pending.add(done.future);
    return Future<T>.sync(operation).whenComplete(() {
      _pending.remove(done.future);
      done.complete();
    });
  }

  Future<void> drain() async {
    _closing = true;
    await Future.wait(_pending.toList());
  }
}
