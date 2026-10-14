import 'dart:async';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

/// Internal session access, deliberately absent from any Feature public entry.
/// Collaborators read the current state and submit synchronous transformations.
/// Only WorkspaceSession owns state, revisions, jobs and cancellation tokens.
abstract interface class WorkspaceWorkflowAccess {
  WorkspaceState get state;
  bool get disposed;
  void ensureOpen();
  void updateState(WorkspaceState Function(WorkspaceState) transform);
  void updateSnapshot(WorkspaceSnapshot Function(WorkspaceSnapshot) transform);
  String nextId(String prefix);
  WorkspaceCancellation registerCancellation(String id);
  WorkspaceCancellation? cancellationFor(String id);
  void releaseCancellation(String id, WorkspaceCancellation? token);
  WorkspaceJob job(String id);
  void putJob(WorkspaceJob job);
  void updateJob(
    String id,
    JobStatus status, {
    String? error,
    int? bytes,
    int? total,
    bool? indeterminate,
  });
  bool isJobCancelled(String id);
  String createDocument({required String title, required String text});
  String beginThumbnail(String assetId);
  Future<void> failThumbnail(String assetId, String error, {String? jobId});
  Future<void> finishCancelledThumbnail(String jobId);
  Future<WorkspaceSaveResult> save();
  Future<void> persistReferenceRollback(
    WorkspaceSnapshot snapshot,
    void Function() retainCommittedContent,
  );
}

final class WorkspaceCancellation {
  final _completion = Completer<void>();
  bool get cancelled => _completion.isCompleted;
  Future<void> get whenCancelled => _completion.future;
  void cancel() {
    if (!cancelled) _completion.complete();
  }

  void check() {
    if (cancelled) throw const WorkspaceCancelled();
  }
}

final class WorkspaceCancelled implements Exception {
  const WorkspaceCancelled();
}

final class WorkspaceReferenceRollbackFailed implements Exception {
  const WorkspaceReferenceRollbackFailed(this.message);
  final String message;
  @override
  String toString() => '回滚保存失败，已保留可用内容：$message';
}

final class WorkspaceSaveResult {
  const WorkspaceSaveResult.saved(this.revision) : error = null;
  const WorkspaceSaveResult.failed(this.error) : revision = null;
  final int? revision;
  final String? error;
  bool get succeeded => revision != null;
}
