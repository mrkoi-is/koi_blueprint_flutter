import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'package:workbench_app/features/workspace/application/internal/workspace_workflow_access.dart';

/// Owns file selection, input leases and the serial import pipeline.
/// Every state read reaches the session; this workflow retains no mutable snapshot.
final class WorkspaceImportWorkflow {
  WorkspaceImportWorkflow({
    required this._access,
    required this.assetStore,
    required this._fileImportPort,
    required this._limits,
    required this._generateImage,
  });
  final WorkspaceWorkflowAccess _access;
  final AssetStore assetStore;
  final FileImportPort _fileImportPort;
  final ImportLimits _limits;
  final Future<void> Function(String) _generateImage;
  Future<void> _importPending = Future.value();
  bool _selecting = false;
  bool get isSelecting => _selecting;
  WorkspaceState get _state => _access.state;
  bool get _disposed => _access.disposed;
  void _change(WorkspaceSnapshot snapshot) =>
      _access.updateSnapshot((_) => snapshot);

  /// A system picker cannot be dismissed. Its cancelled token releases late
  /// inputs without touching storage; callers need not wait for that UI to close.
  Future<void> drain() async {
    if (!_selecting) await _importPending;
  }

  Future<void> enqueue(ImportKind kind, {WorkspaceJob? retry}) {
    _access.ensureOpen();
    if (retry != null) _access.putJob(retry);
    final id = retry?.id ?? _access.nextId('import');
    final cancellation = _access.registerCancellation(id);
    _access.putJob(
      WorkspaceJob(
        id: id,
        kind: JobKind.importFiles,
        name: kind == ImportKind.text ? '导入文本资料' : '导入媒体素材',
        importKind: kind,
        currentAttempt: (retry?.currentAttempt ?? 0) + 1,
      ),
    );
    final operation = _importPending.then(
      (_) => _import(id, kind, cancellation),
    );
    _importPending = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _import(
    String id,
    ImportKind kind,
    WorkspaceCancellation cancellation,
  ) async {
    var committedBytes = 0;
    var ownedSources = <ImportSource>[];
    var finalStatus = JobStatus.succeeded;
    String? finalError;
    var rollbackFailed = false;
    try {
      cancellation.check();
      _access.updateJob(id, JobStatus.running, indeterminate: true);
      _selecting = true;
      late final FileImportResult selection;
      try {
        selection = await _fileImportPort.select(kind);
      } finally {
        _selecting = false;
      }
      final files = switch (selection) {
        FilesSelected(:final files) => files,
        ImportCancelled() => throw const WorkspaceCancelled(),
        ImportFailed(:final message) ||
        ImportUnavailable(:final message) => throw StateError(message),
      };
      ownedSources = files;
      cancellation.check();
      final total = files.fold<int>(
        0,
        (sum, source) => sum + source.byteLength,
      );
      _access.updateJob(id, JobStatus.running, total: total);
      for (final source in files) {
        cancellation.check();
        _access.updateJob(id, JobStatus.running, indeterminate: true);
        final extension = source.name.toLowerCase().split('.').last;
        final mediaKind = extension == 'mp4'
            ? MediaKind.video
            : MediaKind.image;
        final limit = kind == ImportKind.text
            ? _limits.text
            : mediaKind == MediaKind.image
            ? _limits.image
            : _limits.video;
        if (source.byteLength < 0 || source.byteLength > limit) {
          throw StateError('${source.name} 超过文件大小上限 $limit 字节');
        }
        if (kind == ImportKind.text && !['txt', 'md'].contains(extension) ||
            kind == ImportKind.media &&
                !['jpg', 'jpeg', 'png', 'mp4'].contains(extension)) {
          throw StateError('不支持的文件类型：${source.name}');
        }
        if (kind == ImportKind.text) {
          final builder = BytesBuilder(copy: false);
          var count = 0;
          await for (final chunk in _cancellableRead(source, cancellation)) {
            count += chunk.length;
            if (count > limit) throw StateError('${source.name} 超过文件大小上限');
            builder.add(chunk);
            _access.updateJob(
              id,
              JobStatus.running,
              bytes: committedBytes + count,
              total: total,
              indeterminate: false,
            );
          }
          cancellation.check();
          if (count != source.byteLength) {
            throw StateError('${source.name} 读取长度不一致');
          }
          _access.updateJob(id, JobStatus.running, indeterminate: true);
          final text = utf8.decode(builder.takeBytes());
          final previousSelection =
              _state.snapshot.preferences.selectedDocumentId;
          final documentId = _access.createDocument(
            title: source.name,
            text: text,
          );
          committedBytes += count;
          final saved = await _access.save();
          if (!saved.succeeded) throw StateError(saved.error!);
          if (cancellation.cancelled) {
            final committedDocument = _state.snapshot.documents.firstWhere(
              (document) => document.id == documentId,
            );
            await _access.persistReferenceRollback(
              _state.snapshot.copyWith(
                documents: _state.snapshot.documents
                    .where((document) => document.id != documentId)
                    .toList(),
                preferences: _state.snapshot.preferences.copyWith(
                  selectedDocumentId:
                      _state.snapshot.preferences.selectedDocumentId ==
                          documentId
                      ? previousSelection
                      : _state.snapshot.preferences.selectedDocumentId,
                ),
              ),
              () => _change(
                _state.snapshot.copyWith(
                  documents: [..._state.snapshot.documents, committedDocument],
                ),
              ),
            );
            cancellation.check();
          }
        } else {
          String? staged;
          String? committed;
          var recorded = false;
          try {
            final header = <int>[];
            staged = await assetStore.stage(
              _cancellableRead(source, cancellation).map((chunk) {
                if (header.length < 16) {
                  header.addAll(chunk.take(16 - header.length));
                }
                return chunk;
              }),
              name: source.name,
              onBytes: (count) {
                if (count > limit) throw StateError('${source.name} 超过文件大小上限');
                _access.updateJob(
                  id,
                  JobStatus.running,
                  bytes: committedBytes + count,
                  total: total,
                  indeterminate: false,
                );
              },
            );
            cancellation.check();
            final bytes = _access.job(id).processedBytes - committedBytes;
            if (bytes != source.byteLength) {
              throw StateError('${source.name} 读取长度不一致');
            }
            _access.updateJob(id, JobStatus.running, indeterminate: true);
            _validateHeader(extension, header);
            committed = await assetStore.commit(staged);
            staged = null;
            cancellation.check();
            final assetId = _access.nextId('media');
            _change(
              _state.snapshot.copyWith(
                assets: [
                  ..._state.snapshot.assets,
                  WorkspaceAsset(
                    id: assetId,
                    name: source.name,
                    kind: mediaKind,
                    byteLength: bytes,
                    storageKey: committed,
                  ),
                ],
                preferences: _state.snapshot.preferences.copyWith(
                  selectedAssetId: assetId,
                ),
              ),
            );
            final saved = await _access.save();
            if (!saved.succeeded) throw StateError(saved.error!);
            cancellation.check();
            recorded = true;
            committedBytes += bytes;
            if (mediaKind == MediaKind.image && !cancellation.cancelled) {
              await _generateImage(assetId);
            }
          } finally {
            if (!_disposed) {
              _access.updateJob(id, JobStatus.running, indeterminate: true);
            }
            if (staged != null) {
              await assetStore.abort(staged);
            }
            if (committed != null && !recorded) {
              final retained = _state.snapshot.assets
                  .where((asset) => asset.storageKey == committed)
                  .firstOrNull;
              final remaining = _state.snapshot.assets
                  .where((asset) => asset.storageKey != committed)
                  .toList();
              final selected = _state.snapshot.preferences.selectedAssetId;
              final rollback = _state.snapshot.copyWith(
                assets: remaining,
                preferences: _state.snapshot.preferences.copyWith(
                  selectedAssetId:
                      remaining.any((asset) => asset.id == selected)
                      ? selected
                      : remaining.firstOrNull?.id,
                ),
              );
              // Any queued save can persist a reference as soon as it enters
              // the session, even when this import's own save later fails.
              if (retained != null) {
                await _access.persistReferenceRollback(
                  rollback,
                  () => _change(
                    _state.snapshot.copyWith(
                      assets: [..._state.snapshot.assets, retained],
                    ),
                  ),
                );
              } else {
                _change(rollback);
              }
              await assetStore.remove(committed);
            }
          }
        }
      }
      cancellation.check();
      _access.updateJob(
        id,
        JobStatus.running,
        bytes: committedBytes,
        total: total,
        indeterminate: true,
      );
    } on WorkspaceCancelled {
      finalStatus = JobStatus.cancelled;
    } on WorkspaceReferenceRollbackFailed catch (error) {
      rollbackFailed = true;
      finalStatus = JobStatus.failed;
      finalError = error.toString();
    } catch (error) {
      finalStatus = cancellation.cancelled
          ? JobStatus.cancelled
          : JobStatus.failed;
      finalError = cancellation.cancelled ? null : error.toString();
    } finally {
      if (!_disposed) {
        _access.updateJob(id, JobStatus.running, indeterminate: true);
      }
      final cleanupErrors = <String>[];
      for (final source in ownedSources) {
        try {
          await source.close();
        } catch (error) {
          cleanupErrors.add('${source.name}: $error');
        }
      }
      if (cleanupErrors.isNotEmpty) {
        finalStatus = JobStatus.failed;
        finalError =
            '${finalError == null ? '' : '$finalError；'}释放导入源失败：${cleanupErrors.join('；')}';
      } else if (cancellation.cancelled && !rollbackFailed) {
        finalStatus = JobStatus.cancelled;
        finalError = null;
      }
      _access.releaseCancellation(id, cancellation);
      if (!_disposed) {
        _access.updateJob(id, finalStatus, error: finalError);
        await _access.save();
      }
    }
  }

  void _validateHeader(String extension, List<int> bytes) {
    final valid = switch (extension) {
      'png' =>
        bytes.length >= 8 &&
            bytes.take(8).join(',') == '137,80,78,71,13,10,26,10',
      'jpg' || 'jpeg' =>
        bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255,
      'mp4' =>
        bytes.length >= 12 &&
            ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp',
      _ => false,
    };
    if (!valid) throw StateError('素材内容与文件类型不符');
  }

  Stream<List<int>> _cancellableRead(
    ImportSource source,
    WorkspaceCancellation cancellation,
  ) async* {
    final iterator = StreamIterator(source.openRead());
    try {
      while (true) {
        cancellation.check();
        final hasNext = await Future.any<bool>([
          iterator.moveNext(),
          cancellation.whenCancelled.then(
            (_) => throw const WorkspaceCancelled(),
          ),
        ]);
        cancellation.check();
        if (!hasNext) break;
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }
}
