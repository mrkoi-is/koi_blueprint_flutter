import 'dart:async';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'package:workbench_app/features/workspace/application/internal/workspace_workflow_access.dart';
import 'package:workbench_app/features/workspace/application/workspace_import_workflow.dart';
import 'package:workbench_app/features/workspace/application/workspace_persistence.dart';
import 'package:workbench_app/features/workspace/application/workspace_thumbnail_workflow.dart';

export 'package:workbench_app/features/workspace/application/internal/workspace_workflow_access.dart'
    show WorkspaceSaveResult;

/// Sole owner of business state, revisions, tasks and cancellation.
/// Providers and workflows borrow the session; bootstrap owns its IO resources.
final class WorkspaceSession {
  WorkspaceSession({
    required WorkspaceRepository repository,
    required this.assetStore,
    required FileImportPort fileImportPort,
    ImportLimits limits = const ImportLimits(),
    Future<List<int>> Function(List<int>)? imageThumbnail,
    Duration debounce = const Duration(milliseconds: 500),
    this._progressInterval = const Duration(milliseconds: 100),
    this._checkpointInterval = const Duration(seconds: 2),
    this._historyLimit = 200,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       assert(_historyLimit > 0),
       assert(!_progressInterval.isNegative),
       assert(!_checkpointInterval.isNegative) {
    final access = _WorkspaceSessionAccess(this);
    _persistence = WorkspacePersistence(
      access: access,
      repository: repository,
      debounce: debounce,
      beforeSave: _flushProgress,
    );
    _thumbnails = WorkspaceThumbnailWorkflow(
      access: access,
      assetStore: assetStore,
      imageThumbnail: imageThumbnail,
    );
    _imports = WorkspaceImportWorkflow(
      access: access,
      assetStore: assetStore,
      fileImportPort: fileImportPort,
      limits: limits,
      generateImage: _thumbnails.generateImage,
    );
  }

  final AssetStore assetStore;
  late final WorkspacePersistence _persistence;
  late final WorkspaceImportWorkflow _imports;
  late final WorkspaceThumbnailWorkflow _thumbnails;
  Future<void>? _closing;
  final Duration _progressInterval;
  final Duration _checkpointInterval;
  final int _historyLimit;
  final DateTime Function() _clock;
  final Map<String, WorkspaceJob> _pendingProgress = {};
  Timer? _progressTimer;
  DateTime? _lastProgressCheckpoint;
  final _changes = StreamController<WorkspaceState>.broadcast();
  WorkspaceState _state = const WorkspaceState();
  WorkspaceState get state => _state;
  Stream<WorkspaceState> get changes => _changes.stream;
  final Map<String, WorkspaceCancellation> _cancellations = {};
  bool _disposed = false;
  bool _preparingToClose = false;
  bool get preparingToClose => _preparingToClose;
  Future<WorkspaceSaveResult>? _preparation;
  int _nextId = 0;

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';
  void _ensureOpen() {
    if (_disposed) throw StateError('工作区会话已关闭');
    if (_preparingToClose) throw StateError('工作区正在保存并关闭');
  }

  void _emit(WorkspaceState value) {
    _state = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  void _change(WorkspaceSnapshot value, {bool schedule = true}) {
    _emit(
      _state.copyWith(
        snapshot: value.copyWith(revision: _state.snapshot.revision + 1),
        error: null,
      ),
    );
    if (schedule && !_disposed && !_preparingToClose) {
      _persistence.scheduleSave();
    }
  }

  void clearError() => _emit(_state.copyWith(error: null));

  Future<void> initialize() async {
    _ensureOpen();
    try {
      final snapshot = await _persistence.load();
      if (_disposed) return;
      await assetStore.cleanupStaging();
      if (_disposed) return;
      final recovered = snapshot.copyWith(
        jobHistory: snapshot.jobHistory.length > _historyLimit
            ? snapshot.jobHistory.sublist(
                snapshot.jobHistory.length - _historyLimit,
              )
            : snapshot.jobHistory,
        jobs: snapshot.jobs
            .map(
              (job) => job.terminal
                  ? job
                  : job.copyWith(
                      status: JobStatus.interrupted,
                      error: '应用上次关闭时任务未完成',
                    ),
            )
            .toList(),
        assets: snapshot.assets
            .map(
              (asset) => asset.thumbnailStatus == ThumbnailStatus.generating
                  ? asset.copyWith(
                      thumbnailStatus: ThumbnailStatus.failed,
                      thumbnailError: '上次缩略图任务中断，可重试',
                    )
                  : asset,
            )
            .toList(),
      );
      _emit(
        _state.copyWith(snapshot: recovered, initialized: true, error: null),
      );
      if (recovered != snapshot) {
        for (final job in recovered.jobs.where((job) => job.terminal)) {
          _putJob(job);
        }
        final result = await save();
        if (!result.succeeded) throw WorkspaceStorageException(result.error!);
      }
    } catch (error) {
      if (!_disposed) {
        _emit(_state.copyWith(initialized: false, error: error.toString()));
      }
      rethrow;
    }
  }

  String createDocument({String title = '未命名资料', String text = ''}) {
    _ensureOpen();
    final id = _id('document');
    final snapshot = _state.snapshot;
    _change(
      snapshot.copyWith(
        documents: [
          ...snapshot.documents,
          WorkspaceDocument(id: id, title: title, text: text, revision: 1),
        ],
        preferences: snapshot.preferences.copyWith(selectedDocumentId: id),
      ),
    );
    return id;
  }

  void editDocument(String id, String text) {
    _ensureOpen();
    _change(
      _state.snapshot.copyWith(
        documents: _state.snapshot.documents
            .map(
              (document) => document.id == id
                  ? document.copyWith(
                      text: text,
                      revision: document.revision + 1,
                    )
                  : document,
            )
            .toList(),
      ),
    );
  }

  void renameDocument(String id, String title) {
    _ensureOpen();
    _change(
      _state.snapshot.copyWith(
        documents: _state.snapshot.documents
            .map(
              (document) => document.id == id
                  ? document.copyWith(
                      title: title,
                      revision: document.revision + 1,
                    )
                  : document,
            )
            .toList(),
      ),
    );
  }

  void deleteDocument(String id) {
    _ensureOpen();
    final snapshot = _state.snapshot;
    _change(
      snapshot.copyWith(
        documents: snapshot.documents
            .where((document) => document.id != id)
            .toList(),
        preferences: snapshot.preferences.copyWith(
          selectedDocumentId: snapshot.preferences.selectedDocumentId == id
              ? null
              : snapshot.preferences.selectedDocumentId,
        ),
      ),
    );
  }

  void deleteDocuments(Set<String> ids) {
    _ensureOpen();
    final snapshot = _state.snapshot;
    _change(
      snapshot.copyWith(
        documents: snapshot.documents
            .where((item) => !ids.contains(item.id))
            .toList(),
        preferences: snapshot.preferences.copyWith(
          selectedDocumentId:
              ids.contains(snapshot.preferences.selectedDocumentId)
              ? null
              : snapshot.preferences.selectedDocumentId,
        ),
      ),
    );
  }

  void reorderDocuments(List<String> ids) {
    _ensureOpen();
    final documents = {
      for (final item in _state.snapshot.documents) item.id: item,
    };
    if (ids.length != documents.length ||
        ids.toSet().length != ids.length ||
        !ids.every(documents.containsKey)) {
      throw ArgumentError(
        'Reordering must preserve every document ID exactly once',
      );
    }
    _change(
      _state.snapshot.copyWith(
        documents: ids.map((id) => documents[id]!).toList(),
      ),
    );
  }

  void updatePreferences(WorkspacePreferences value) {
    _ensureOpen();
    _change(_state.snapshot.copyWith(preferences: value));
  }

  String addTodo(String title) {
    _ensureOpen();
    final id = _id('todo');
    _change(
      _state.snapshot.copyWith(
        todos: [
          ..._state.snapshot.todos,
          WorkspaceTodo(id: id, title: title),
        ],
      ),
    );
    return id;
  }

  void updateTodo(String id, {String? title, bool? completed}) {
    _ensureOpen();
    _change(
      _state.snapshot.copyWith(
        todos: _state.snapshot.todos
            .map(
              (todo) => todo.id == id
                  ? todo.copyWith(
                      title: title ?? todo.title,
                      completed: completed ?? todo.completed,
                    )
                  : todo,
            )
            .toList(),
      ),
    );
  }

  void deleteTodo(String id) {
    _ensureOpen();
    _change(
      _state.snapshot.copyWith(
        todos: _state.snapshot.todos.where((todo) => todo.id != id).toList(),
      ),
    );
  }

  /// Captures each revision at execution time; later edits stay dirty.
  Future<WorkspaceSaveResult> save() => _persistence.save();

  /// Roll back durable references before their bytes can be removed.
  Future<void> _persistReferenceRollback(
    WorkspaceSnapshot snapshot,
    void Function() retainCommittedContent,
  ) async {
    _change(snapshot);
    final result = await save();
    final error = result.error;
    if (!result.succeeded && error != null) {
      retainCommittedContent();
      _emit(_state.copyWith(error: error));
      throw WorkspaceReferenceRollbackFailed(error);
    }
  }

  void _putJob(WorkspaceJob job) {
    _pendingProgress.remove(job.id);
    final jobs = _state.snapshot.jobs;
    var history = _state.snapshot.jobHistory;
    if (job.terminal) {
      history = [
        ...history.where(
          (entry) =>
              entry.id != job.id || entry.currentAttempt != job.currentAttempt,
        ),
        job,
      ];
      if (history.length > _historyLimit) {
        history = history.sublist(history.length - _historyLimit);
      }
    }
    _change(
      _state.snapshot.copyWith(
        jobs: jobs.any((value) => value.id == job.id)
            ? jobs.map((value) => value.id == job.id ? job : value).toList()
            : [...jobs, job],
        jobHistory: history,
      ),
    );
  }

  WorkspaceJob _job(String id) =>
      _pendingProgress[id] ??
      _state.snapshot.jobs.firstWhere((job) => job.id == id);

  /// Latest terminal attempts, independently queryable from current task state.
  List<WorkspaceJob> readJobHistory({String? jobId, int limit = 50}) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    return List.unmodifiable(
      _state.snapshot.jobHistory.reversed
          .where((job) => jobId == null || job.id == jobId)
          .take(limit),
    );
  }

  Future<WorkspaceSaveResult> clearJobHistory() {
    _ensureOpen();
    _change(_state.snapshot.copyWith(jobHistory: []));
    return save();
  }

  /// Byte events are sampled for observers. Only periodic checkpoints increase
  /// the durable revision; phase changes and terminal states bypass sampling.
  void _flushProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (_pendingProgress.isEmpty) return;
    final next = _state.snapshot.copyWith(
      jobs: [
        for (final job in _state.snapshot.jobs) _pendingProgress[job.id] ?? job,
      ],
    );
    _pendingProgress.clear();
    final now = _clock();
    if (_lastProgressCheckpoint == null ||
        now.difference(_lastProgressCheckpoint!) >= _checkpointInterval) {
      _lastProgressCheckpoint = now;
      _change(next);
    } else {
      _emit(_state.copyWith(snapshot: next));
    }
  }

  void _updateJob(
    String id,
    JobStatus status, {
    String? error,
    int? bytes,
    int? total,
    bool? indeterminate,
  }) {
    final current = _job(id);
    if (current.terminal) return;
    var next = current.copyWith(
      status:
          current.status == JobStatus.cancelling && status == JobStatus.running
          ? JobStatus.cancelling
          : status,
      error: error,
      processedBytes: bytes ?? current.processedBytes,
      totalBytes: total ?? current.totalBytes,
      indeterminate: current.status == JobStatus.cancelling
          ? true
          : indeterminate ?? current.indeterminate,
      startedAt:
          current.startedAt ??
          (status == JobStatus.running ? _clock().toUtc() : null),
    );
    if (next.terminal) next = next.copyWith(finishedAt: _clock().toUtc());
    if (bytes != null &&
        next.status == JobStatus.running &&
        current.status == next.status &&
        current.indeterminate == next.indeterminate &&
        current.error == next.error &&
        current.totalBytes == next.totalBytes) {
      _pendingProgress[id] = next;
      _progressTimer ??= Timer(_progressInterval, _flushProgress);
      return;
    }
    _flushProgress();
    _putJob(next);
  }

  void cancelJob(String id) {
    _ensureOpen();
    final job = _job(id);
    if (job.terminal) return;
    _cancellations[id]?.cancel();
    _updateJob(id, JobStatus.cancelling, indeterminate: true);
  }

  bool isJobCancelled(String id) =>
      _disposed ||
      (_cancellations[id]?.cancelled ??
          _state.snapshot.jobs
              .where((job) => job.id == id)
              .any(
                (job) => job.terminal || job.status == JobStatus.cancelling,
              ));

  Future<void> importFiles(ImportKind kind) => _imports.enqueue(kind);

  String beginThumbnail(String assetId) {
    _ensureOpen();
    final asset = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == assetId,
    );
    final retry = _state.snapshot.jobs
        .where(
          (job) =>
              job.kind == JobKind.thumbnail &&
              job.assetId == assetId &&
              job.terminal &&
              job.status != JobStatus.succeeded,
        )
        .lastOrNull;
    if (retry != null) _putJob(retry);
    final id = retry?.id ?? _id('thumbnail');
    _cancellations[id] = WorkspaceCancellation();
    _putJob(
      WorkspaceJob(
        id: id,
        kind: JobKind.thumbnail,
        name: '${asset.name} 缩略图',
        assetId: assetId,
        status: JobStatus.running,
        currentAttempt: (retry?.currentAttempt ?? 0) + 1,
        startedAt: _clock().toUtc(),
      ),
    );
    _change(
      _state.snapshot.copyWith(
        assets: _state.snapshot.assets
            .map(
              (value) => value.id == assetId
                  ? value.copyWith(
                      thumbnailStatus: ThumbnailStatus.generating,
                      thumbnailError: null,
                    )
                  : value,
            )
            .toList(),
      ),
    );
    return id;
  }

  Future<void> storeThumbnail(
    String assetId,
    List<int> bytes, {
    String? jobId,
  }) => _thumbnails.store(assetId, bytes, jobId: jobId);

  Future<void> failThumbnail(
    String assetId,
    String error, {
    String? jobId,
  }) async {
    final id = jobId ?? beginThumbnail(assetId);
    if (isJobCancelled(id)) {
      await finishCancelledThumbnail(id);
      return;
    }
    _change(
      _state.snapshot.copyWith(
        assets: _state.snapshot.assets
            .map(
              (asset) => asset.id == assetId
                  ? asset.copyWith(
                      thumbnailStatus: ThumbnailStatus.failed,
                      thumbnailError: error,
                    )
                  : asset,
            )
            .toList(),
      ),
    );
    _updateJob(id, JobStatus.failed, error: error);
    _cancellations.remove(id);
    if (!_disposed) await save();
  }

  Future<void> finishCancelledThumbnail(String jobId) async {
    if (_disposed) return;
    final job = _job(jobId);
    if (job.terminal) return;
    _change(
      _state.snapshot.copyWith(
        assets: _state.snapshot.assets
            .map(
              (asset) => asset.id == job.assetId
                  ? asset.copyWith(
                      thumbnailStatus: asset.thumbnailKey == null
                          ? ThumbnailStatus.none
                          : ThumbnailStatus.ready,
                      thumbnailError: null,
                    )
                  : asset,
            )
            .toList(),
      ),
    );
    _updateJob(jobId, JobStatus.cancelled);
    _cancellations.remove(jobId);
    await save();
  }

  Future<void> retryJob(String id) async {
    _ensureOpen();
    final job = _job(id);
    if (!job.terminal) return;
    if (job.kind == JobKind.importFiles) {
      await _imports.enqueue(job.importKind ?? ImportKind.media, retry: job);
      return;
    }
    final asset = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == job.assetId,
    );
    if (asset.kind == MediaKind.video) throw StateError('请打开对应视频预览重试缩略图');
    await _thumbnails.generateImage(asset.id);
  }

  /// Reversible close preparation. Do not dispose a session before this succeeds.
  Future<WorkspaceSaveResult> prepareToClose() =>
      _preparation ??= _prepareToClose();

  Future<WorkspaceSaveResult> _prepareToClose() async {
    _preparingToClose = true;
    _flushProgress();
    _persistence.cancelScheduledSave();
    for (final entry in _cancellations.entries.toList()) {
      entry.value.cancel();
      _updateJob(entry.key, JobStatus.cancelling, indeterminate: true);
    }
    try {
      if (_imports.isSelecting) {
        // A system picker cannot be dismissed by the application. Mark these
        // cancelled now; its token rejects late files before any storage access.
        for (final job
            in _state.snapshot.jobs
                .where(
                  (job) => job.kind == JobKind.importFiles && !job.terminal,
                )
                .toList()) {
          _updateJob(job.id, JobStatus.cancelled);
        }
      } else {
        await _imports.drain();
      }
      await _thumbnails.drain();
      final result = await save();
      if (!result.succeeded) {
        _preparingToClose = false;
        _preparation = null;
      }
      return result;
    } catch (error) {
      _preparingToClose = false;
      _preparation = null;
      final message = '关闭前保存失败：$error';
      _emit(_state.copyWith(error: message));
      return WorkspaceSaveResult.failed(message);
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _flushProgress();
    _progressTimer?.cancel();
    _disposed = true;
    _persistence.cancelScheduledSave();
    for (final cancellation in _cancellations.values) {
      cancellation.cancel();
    }
    // A system picker has no programmatic dismiss API. Its late result is
    // discarded before any storage access; do not block shutdown on that UI.
    if (!_imports.isSelecting) await _imports.drain();
    await _thumbnails.drain();
    if (!_preparingToClose) await save();
    await _changes.close();
  }
}

/// One adapter delegates into the current owner; it cannot retain writable state.
final class _WorkspaceSessionAccess implements WorkspaceWorkflowAccess {
  const _WorkspaceSessionAccess(this.owner);
  final WorkspaceSession owner;
  @override
  WorkspaceState get state => owner.state;
  @override
  bool get disposed => owner._disposed;
  @override
  void ensureOpen() => owner._ensureOpen();
  @override
  void updateState(WorkspaceState Function(WorkspaceState) transform) =>
      owner._emit(transform(owner._state));
  @override
  void updateSnapshot(
    WorkspaceSnapshot Function(WorkspaceSnapshot) transform,
  ) => owner._change(transform(owner._state.snapshot));
  @override
  String nextId(String prefix) => owner._id(prefix);
  @override
  WorkspaceCancellation registerCancellation(String id) =>
      owner._cancellations[id] = WorkspaceCancellation();
  @override
  WorkspaceCancellation? cancellationFor(String id) => owner._cancellations[id];
  @override
  void releaseCancellation(String id, WorkspaceCancellation? token) {
    if (identical(owner._cancellations[id], token)) {
      owner._cancellations.remove(id);
    }
  }

  @override
  WorkspaceJob job(String id) => owner._job(id);
  @override
  void putJob(WorkspaceJob job) => owner._putJob(job);
  @override
  void updateJob(
    String id,
    JobStatus status, {
    String? error,
    int? bytes,
    int? total,
    bool? indeterminate,
  }) => owner._updateJob(
    id,
    status,
    error: error,
    bytes: bytes,
    total: total,
    indeterminate: indeterminate,
  );
  @override
  bool isJobCancelled(String id) => owner.isJobCancelled(id);
  @override
  String createDocument({required String title, required String text}) =>
      owner.createDocument(title: title, text: text);
  @override
  String beginThumbnail(String assetId) => owner.beginThumbnail(assetId);
  @override
  Future<void> failThumbnail(String assetId, String error, {String? jobId}) =>
      owner.failThumbnail(assetId, error, jobId: jobId);
  @override
  Future<void> finishCancelledThumbnail(String jobId) =>
      owner.finishCancelledThumbnail(jobId);
  @override
  Future<WorkspaceSaveResult> save() => owner.save();
  @override
  Future<void> persistReferenceRollback(
    WorkspaceSnapshot snapshot,
    void Function() retainCommittedContent,
  ) => owner._persistReferenceRollback(snapshot, retainCommittedContent);
}
