import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'package:workbench_app/features/workspace/application/internal/workspace_workflow_access.dart';

/// Owns conversion and thumbnail bytes, borrowing storage from bootstrap.
/// References are saved before deleting replaced or cancelled files.
final class WorkspaceThumbnailWorkflow {
  WorkspaceThumbnailWorkflow({
    required this._access,
    required this.assetStore,
    this._imageThumbnail,
  });
  final WorkspaceWorkflowAccess _access;
  final AssetStore assetStore;
  final Future<List<int>> Function(List<int>)? _imageThumbnail;
  final Set<Future<void>> _pending = {};
  WorkspaceState get _state => _access.state;
  bool get _disposed => _access.disposed;
  void _change(WorkspaceSnapshot snapshot) =>
      _access.updateSnapshot((_) => snapshot);
  void _emit(WorkspaceState state) => _access.updateState((_) => state);
  Future<void> drain() => Future.wait(_pending.toList());

  Future<void> store(String assetId, List<int> bytes, {String? jobId}) =>
      _track(_store(assetId, bytes, jobId: jobId));

  /// Closing waits through every write's compensation and final cleanup, whether
  /// it originated in image conversion or the public supplied-thumbnail entry.
  Future<void> _track(Future<void> operation) {
    late final Future<void> pending;
    pending = operation.whenComplete(() => _pending.remove(pending));
    _pending.add(pending);
    return pending;
  }

  Future<void> _store(String assetId, List<int> bytes, {String? jobId}) async {
    final id = jobId ?? _access.beginThumbnail(assetId);
    final cancellation = _access.cancellationFor(id);
    final original = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == assetId,
    );
    String? staged;
    String? committed;
    var referencePublished = false;
    try {
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      _access.updateJob(
        id,
        JobStatus.running,
        total: bytes.length,
        indeterminate: true,
      );
      final jpeg = bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 216;
      staged = await assetStore.stage(
        Stream.value(bytes),
        name: jpeg ? 'thumbnail.jpg' : 'thumbnail.png',
        onBytes: (count) => _access.updateJob(
          id,
          JobStatus.running,
          bytes: count,
          total: bytes.length,
          indeterminate: false,
        ),
      );
      _access.updateJob(id, JobStatus.running, indeterminate: true);
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      committed = await assetStore.commit(staged);
      staged = null;
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      final oldKey = _state.snapshot.assets
          .firstWhere((asset) => asset.id == assetId)
          .thumbnailKey;
      _change(
        _state.snapshot.copyWith(
          assets: _state.snapshot.assets
              .map(
                (asset) => asset.id == assetId
                    ? asset.copyWith(
                        thumbnailKey: committed,
                        thumbnailStatus: ThumbnailStatus.ready,
                        thumbnailError: null,
                      )
                    : asset,
              )
              .toList(),
        ),
      );
      referencePublished = true;
      final saved = await _access.save();
      if (!saved.succeeded) throw StateError(saved.error!);
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      committed = null;
      if (oldKey != null) await assetStore.remove(oldKey);
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      _access.updateJob(id, JobStatus.succeeded);
    } catch (error) {
      if (staged != null) {
        await assetStore.abort(staged);
        staged = null;
      }
      final cleanupKey = committed;
      // Once published, another queued save may already reference these bytes.
      // Relinquish unconditional cleanup before awaiting compensation so every
      // failed rollback retains recoverable content, including ordinary errors.
      committed = null;
      if (cleanupKey != null) {
        if (referencePublished) {
          final retained = _state.snapshot.assets.firstWhere(
            (asset) => asset.id == assetId,
          );
          try {
            await _access.persistReferenceRollback(
              _withThumbnail(
                original.copyWith(
                  thumbnailStatus: original.thumbnailKey == null
                      ? ThumbnailStatus.none
                      : ThumbnailStatus.ready,
                  thumbnailError: null,
                ),
              ),
              () => _change(_withThumbnail(retained)),
            );
          } on WorkspaceReferenceRollbackFailed catch (rollbackError) {
            _access.updateJob(
              id,
              JobStatus.failed,
              error: rollbackError.toString(),
            );
            _emit(_state.copyWith(error: rollbackError.toString()));
            return;
          }
        }
        await assetStore.remove(cleanupKey);
      }
      if (error is WorkspaceCancelled || _access.isJobCancelled(id)) {
        await _access.finishCancelledThumbnail(id);
      } else {
        await _access.failThumbnail(assetId, error.toString(), jobId: id);
      }
    } finally {
      if (staged != null) await assetStore.abort(staged);
      if (committed != null) await assetStore.remove(committed);
      _access.releaseCancellation(id, cancellation);
      if (!_disposed) await _access.save();
    }
  }

  // Restore only the thumbnail fields; concurrent metadata edits belong to the
  // session and must not be replaced by an earlier asset snapshot.
  WorkspaceSnapshot _withThumbnail(WorkspaceAsset previous) =>
      _state.snapshot.copyWith(
        assets: _state.snapshot.assets
            .map(
              (asset) => asset.id == previous.id
                  ? asset.copyWith(
                      thumbnailKey: previous.thumbnailKey,
                      thumbnailStatus: previous.thumbnailStatus,
                      thumbnailError: previous.thumbnailError,
                    )
                  : asset,
            )
            .toList(),
      );

  Future<void> generateImage(String assetId) =>
      _track(_runImageThumbnail(assetId));

  Future<void> _runImageThumbnail(String assetId) async {
    final id = _access.beginThumbnail(assetId);
    try {
      final asset = _state.snapshot.assets.firstWhere(
        (asset) => asset.id == assetId,
      );
      final source = await assetStore.readBytes(asset.storageKey);
      if (_access.isJobCancelled(id)) throw const WorkspaceCancelled();
      final converter = _imageThumbnail;
      if (converter == null) throw StateError('未装配图片缩略图实现');
      final thumbnail = await converter(source)
          .timeout(const Duration(seconds: 10));
      await store(assetId, thumbnail, jobId: id);
    } on WorkspaceCancelled {
      await _access.finishCancelledThumbnail(id);
    } catch (error) {
      await _access.failThumbnail(assetId, error.toString(), jobId: id);
    }
  }
}
