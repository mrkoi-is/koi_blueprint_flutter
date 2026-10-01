import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_preview_session.dart';

final class MemoryRepository implements WorkspaceRepository {
  MemoryRepository([this.snapshot = const WorkspaceSnapshot()]);
  WorkspaceSnapshot snapshot;
  int saves = 0;
  bool failLoad = false;
  bool failSave = false;
  Future<void>? saveGate;
  @override
  Future<WorkspaceSnapshot> load() async {
    if (failLoad) {
      throw StateError('read failure');
    }
    return snapshot;
  }

  @override
  Future<void> save(WorkspaceSnapshot value) async {
    await saveGate;
    if (failSave) {
      throw StateError('write failure');
    }
    ++saves;
    snapshot = value;
  }
}

final class MemoryAssetStore implements AssetStore {
  final values = <String, Uint8List>{};
  final failedReads = <String>{};
  int _next = 0;
  @override
  Future<String> stage(
    Stream<List<int>> bytes, {
    required String name,
    void Function(int)? onBytes,
  }) async {
    final builder = BytesBuilder();
    var processed = 0;
    await for (final chunk in bytes) {
      builder.add(chunk);
      onBytes?.call(processed += chunk.length);
    }
    final key = 'stage_${_next++}';
    values[key] = builder.takeBytes();
    return key;
  }

  @override
  Future<String> commit(String stagedKey) async {
    final key = 'asset_${_next++}';
    values[key] = values.remove(stagedKey)!;
    return key;
  }

  @override
  Future<void> abort(String stagedKey) async {
    values.remove(stagedKey);
  }

  @override
  Stream<List<int>> read(String key) =>
      Stream.value(values[key] ?? Uint8List(0));
  @override
  Future<Uint8List> readBytes(String key) async {
    if (failedReads.contains(key)) throw StateError('read failure: $key');
    return values[key] ?? Uint8List(0);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> cleanupStaging() async {
    values.removeWhere((key, _) => key.startsWith('stage_'));
  }
}

final class MemoryStorage implements WorkspaceStorage {
  MemoryStorage([WorkspaceSnapshot snapshot = const WorkspaceSnapshot()])
    : repository = MemoryRepository(snapshot);
  @override
  final MemoryRepository repository;
  @override
  final MemoryAssetStore assetStore = MemoryAssetStore();
  @override
  String? warning;
  int closes = 0;
  int leaseReleases = 0;
  @override
  Future<AssetPreviewLease> openPreview(String key) async =>
      _MemoryLease('test://$key', () {
        ++leaseReleases;
      });
  @override
  Future<void> close() async {
    ++closes;
  }
}

class _MemoryLease implements AssetPreviewLease {
  _MemoryLease(this.uri, this.release);
  @override
  final String uri;
  final void Function() release;
  @override
  Future<void> dispose() async {
    release();
  }
}

final class CancelImport implements FileImportPort {
  @override
  Future<FileImportResult> select(ImportKind kind) async =>
      const ImportCancelled();
}

final class PendingImport implements FileImportPort {
  final result = Completer<FileImportResult>();
  @override
  Future<FileImportResult> select(ImportKind kind) => result.future;
}

final class FakePlayback extends ChangeNotifier implements MediaPlayback {
  FakePlayback({this.onClose});
  final Future<void> Function()? onClose;
  int opens = 0;
  int pauses = 0;
  int closes = 0;
  int screenshots = 0;
  String? openedUri;
  final errorsController = StreamController<String>.broadcast();
  final frame = Completer<void>()..complete();
  Uint8List? screenshotBytes = Uint8List.fromList([1, 2, 3]);
  Completer<Uint8List?>? screenshotPending;
  @override
  Duration position = const Duration(seconds: 7);
  @override
  Duration duration = const Duration(seconds: 30);
  @override
  double volume = 100;
  @override
  bool playing = false;
  @override
  Widget get surface => const ColoredBox(
    color: Colors.black,
    child: Center(
      child: Text('Fake video surface', style: TextStyle(color: Colors.white)),
    ),
  );
  @override
  Stream<String> get errors => errorsController.stream;
  @override
  Future<void> get firstFrame => frame.future;
  @override
  Future<void> open(String uri) async {
    ++opens;
    openedUri = uri;
  }

  @override
  Future<Uint8List?> screenshot() async {
    ++screenshots;
    return screenshotPending?.future ?? screenshotBytes;
  }

  @override
  Future<void> play() async {
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    ++pauses;
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    ++closes;
    try {
      await onClose?.call();
    } finally {
      await errorsController.close();
      super.dispose();
    }
  }
}
