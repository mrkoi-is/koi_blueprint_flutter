import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Owns the workspace state, debounce and tasks. Providers borrow this session.
final class WorkspaceSession {
  WorkspaceSession({
    required this._repository,
    required this.assetStore,
    required this._fileImportPort,
    this._limits = const ImportLimits(),
    this._imageThumbnail,
    this._debounce = const Duration(milliseconds: 500),
  });

  final WorkspaceRepository _repository;
  final AssetStore assetStore;
  final FileImportPort _fileImportPort;
  final ImportLimits _limits;
  final Future<List<int>> Function(List<int>)? _imageThumbnail;
  final Duration _debounce;
  final _changes = StreamController<WorkspaceState>.broadcast();
  WorkspaceState _state = const WorkspaceState();
  WorkspaceState get state => _state;
  Stream<WorkspaceState> get changes => _changes.stream;
  final Map<String, _Cancellation> _cancellations = {};
  Future<void> _savePending = Future.value();
  Future<void> _importPending = Future.value();
  Timer? _timer;
  bool _disposed = false;
  bool _selecting = false;
  int _nextId = 0;

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';
  void _ensureOpen() {
    if (_disposed) throw StateError('工作区会话已关闭');
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
    if (schedule && !_disposed) {
      _timer?.cancel();
      _timer = Timer(_debounce, () {
        unawaited(save());
      });
    }
  }

  void clearError() => _emit(_state.copyWith(error: null));

  Future<void> initialize() async {
    _ensureOpen();
    try {
      final snapshot = await _repository.load();
      if (_disposed) return;
      await assetStore.cleanupStaging();
      if (_disposed) return;
      final recovered = snapshot.copyWith(
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
      if (recovered != snapshot) await save();
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
  Future<void> save() {
    _timer?.cancel();
    final operation = _savePending.then((_) async {
      if (!_state.initialized) return;
      final captured = _state.snapshot;
      final persisted = captured.copyWith(
        documents: captured.documents
            .map(
              (document) => document.copyWith(savedRevision: document.revision),
            )
            .toList(),
      );
      _emit(_state.copyWith(saving: true, error: null));
      try {
        await _repository.save(persisted);
        final revisions = {
          for (final document in captured.documents)
            document.id: document.revision,
        };
        _emit(
          _state.copyWith(
            saving: false,
            snapshot: _state.snapshot.copyWith(
              documents: _state.snapshot.documents
                  .map(
                    (document) => revisions.containsKey(document.id)
                        ? document.copyWith(
                            savedRevision: revisions[document.id]!,
                          )
                        : document,
                  )
                  .toList(),
            ),
          ),
        );
      } catch (error) {
        _emit(_state.copyWith(saving: false, error: '保存失败：$error'));
      }
    });
    _savePending = operation;
    return operation;
  }

  /// Roll back durable references before their bytes can be removed.
  Future<void> _persistCancellationRollback(
    WorkspaceSnapshot snapshot,
    void Function() retainCommittedContent,
  ) async {
    _change(snapshot);
    await save();
    final error = _state.error;
    if (error != null) {
      retainCommittedContent();
      _emit(_state.copyWith(error: error));
      throw _CancellationRollbackFailed(error);
    }
  }

  void _putJob(WorkspaceJob job) {
    final jobs = _state.snapshot.jobs;
    _change(
      _state.snapshot.copyWith(
        jobs: jobs.any((value) => value.id == job.id)
            ? jobs.map((value) => value.id == job.id ? job : value).toList()
            : [...jobs, job],
      ),
    );
  }

  WorkspaceJob _job(String id) =>
      _state.snapshot.jobs.firstWhere((job) => job.id == id);
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
    _putJob(
      current.copyWith(
        status:
            current.status == JobStatus.cancelling &&
                status == JobStatus.running
            ? JobStatus.cancelling
            : status,
        error: error,
        processedBytes: bytes ?? _job(id).processedBytes,
        totalBytes: total ?? _job(id).totalBytes,
        indeterminate: current.status == JobStatus.cancelling
            ? true
            : indeterminate ?? current.indeterminate,
      ),
    );
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

  Future<void> importFiles(ImportKind kind) {
    _ensureOpen();
    final id = _id('import');
    final cancellation = _Cancellation();
    _cancellations[id] = cancellation;
    _putJob(
      WorkspaceJob(
        id: id,
        kind: JobKind.importFiles,
        name: kind == ImportKind.text ? '导入文本资料' : '导入媒体素材',
        importKind: kind,
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
    _Cancellation cancellation,
  ) async {
    var committedBytes = 0;
    var ownedSources = <ImportSource>[];
    var finalStatus = JobStatus.succeeded;
    String? finalError;
    var rollbackFailed = false;
    try {
      cancellation.check();
      _updateJob(id, JobStatus.running, indeterminate: true);
      _selecting = true;
      late final FileImportResult selection;
      try {
        selection = await _fileImportPort.select(kind);
      } finally {
        _selecting = false;
      }
      final files = switch (selection) {
        FilesSelected(:final files) => files,
        ImportCancelled() => throw const _Cancelled(),
        ImportFailed(:final message) ||
        ImportUnavailable(:final message) => throw StateError(message),
      };
      ownedSources = files;
      cancellation.check();
      final total = files.fold<int>(
        0,
        (sum, source) => sum + source.byteLength,
      );
      _updateJob(id, JobStatus.running, total: total);
      for (final source in files) {
        cancellation.check();
        _updateJob(id, JobStatus.running, indeterminate: true);
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
            _updateJob(
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
          _updateJob(id, JobStatus.running, indeterminate: true);
          final text = utf8.decode(builder.takeBytes());
          final previousSelection =
              _state.snapshot.preferences.selectedDocumentId;
          final documentId = createDocument(title: source.name, text: text);
          committedBytes += count;
          await save();
          if (_state.error != null) throw StateError(_state.error!);
          if (cancellation.cancelled) {
            final committedDocument = _state.snapshot.documents.firstWhere(
              (document) => document.id == documentId,
            );
            await _persistCancellationRollback(
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
          var snapshotCommitted = false;
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
                _updateJob(
                  id,
                  JobStatus.running,
                  bytes: committedBytes + count,
                  total: total,
                  indeterminate: false,
                );
              },
            );
            cancellation.check();
            final bytes = _job(id).processedBytes - committedBytes;
            if (bytes != source.byteLength) {
              throw StateError('${source.name} 读取长度不一致');
            }
            _updateJob(id, JobStatus.running, indeterminate: true);
            _validateHeader(extension, header);
            committed = await assetStore.commit(staged);
            staged = null;
            cancellation.check();
            final assetId = _id('media');
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
            await save();
            if (_state.error != null) throw StateError(_state.error!);
            snapshotCommitted = true;
            cancellation.check();
            recorded = true;
            committedBytes += bytes;
            if (mediaKind == MediaKind.image && !cancellation.cancelled) {
              await _generateImageThumbnail(assetId);
            }
          } finally {
            if (!_disposed) {
              _updateJob(id, JobStatus.running, indeterminate: true);
            }
            if (staged != null) await assetStore.abort(staged);
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
              if (snapshotCommitted && retained != null) {
                await _persistCancellationRollback(
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
      _updateJob(
        id,
        JobStatus.running,
        bytes: committedBytes,
        total: total,
        indeterminate: true,
      );
    } on _Cancelled {
      finalStatus = JobStatus.cancelled;
    } on _CancellationRollbackFailed catch (error) {
      rollbackFailed = true;
      finalStatus = JobStatus.failed;
      finalError = error.toString();
    } catch (error) {
      finalStatus = cancellation.cancelled
          ? JobStatus.cancelled
          : JobStatus.failed;
      finalError = cancellation.cancelled ? null : error.toString();
    } finally {
      if (!_disposed) _updateJob(id, JobStatus.running, indeterminate: true);
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
      _cancellations.remove(id);
      if (!_disposed) {
        _updateJob(id, finalStatus, error: finalError);
        await save();
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
    _Cancellation cancellation,
  ) async* {
    final iterator = StreamIterator(source.openRead());
    try {
      while (true) {
        cancellation.check();
        final hasNext = await Future.any<bool>([
          iterator.moveNext(),
          cancellation.whenCancelled.then((_) => throw const _Cancelled()),
        ]);
        cancellation.check();
        if (!hasNext) break;
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  String beginThumbnail(String assetId) {
    _ensureOpen();
    final asset = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == assetId,
    );
    final id = _id('thumbnail');
    _cancellations[id] = _Cancellation();
    _putJob(
      WorkspaceJob(
        id: id,
        kind: JobKind.thumbnail,
        name: '${asset.name} 缩略图',
        assetId: assetId,
        status: JobStatus.running,
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
  }) async {
    final id = jobId ?? beginThumbnail(assetId);
    final original = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == assetId,
    );
    String? staged;
    String? committed;
    try {
      if (isJobCancelled(id)) throw const _Cancelled();
      _updateJob(
        id,
        JobStatus.running,
        total: bytes.length,
        indeterminate: true,
      );
      final jpeg = bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 216;
      staged = await assetStore.stage(
        Stream.value(bytes),
        name: jpeg ? 'thumbnail.jpg' : 'thumbnail.png',
        onBytes: (count) => _updateJob(
          id,
          JobStatus.running,
          bytes: count,
          total: bytes.length,
          indeterminate: false,
        ),
      );
      _updateJob(id, JobStatus.running, indeterminate: true);
      if (isJobCancelled(id)) throw const _Cancelled();
      committed = await assetStore.commit(staged);
      staged = null;
      if (isJobCancelled(id)) throw const _Cancelled();
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
      await save();
      if (_state.error != null) throw StateError(_state.error!);
      if (isJobCancelled(id)) throw const _Cancelled();
      committed = null;
      if (oldKey != null) await assetStore.remove(oldKey);
      if (isJobCancelled(id)) throw const _Cancelled();
      _updateJob(id, JobStatus.succeeded);
    } on _Cancelled {
      if (staged != null) {
        await assetStore.abort(staged);
        staged = null;
      }
      if (committed != null) {
        final retained = _state.snapshot.assets.firstWhere(
          (asset) => asset.id == assetId,
        );
        try {
          await _persistCancellationRollback(
            _state.snapshot.copyWith(
              assets: _state.snapshot.assets
                  .map(
                    (asset) => asset.id == assetId
                        ? original.copyWith(
                            thumbnailStatus: original.thumbnailKey == null
                                ? ThumbnailStatus.none
                                : ThumbnailStatus.ready,
                            thumbnailError: null,
                          )
                        : asset,
                  )
                  .toList(),
            ),
            () => _change(
              _state.snapshot.copyWith(
                assets: _state.snapshot.assets
                    .map((asset) => asset.id == assetId ? retained : asset)
                    .toList(),
              ),
            ),
          );
        } on _CancellationRollbackFailed catch (error) {
          // The durable snapshot can still reference these new bytes.
          committed = null;
          _updateJob(id, JobStatus.failed, error: error.toString());
          _emit(_state.copyWith(error: error.toString()));
          return;
        }
        await assetStore.remove(committed);
        committed = null;
      }
      await finishCancelledThumbnail(id);
    } catch (error) {
      _change(
        _state.snapshot.copyWith(
          assets: _state.snapshot.assets
              .map((asset) => asset.id == assetId ? original : asset)
              .toList(),
        ),
      );
      if (staged != null) {
        await assetStore.abort(staged);
        staged = null;
      }
      if (committed != null) {
        await assetStore.remove(committed);
        committed = null;
      }
      await failThumbnail(assetId, error.toString(), jobId: id);
    } finally {
      if (staged != null) await assetStore.abort(staged);
      if (committed != null) await assetStore.remove(committed);
      _cancellations.remove(id);
      if (!_disposed) await save();
    }
  }

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

  Future<void> _generateImageThumbnail(String assetId) async {
    final id = beginThumbnail(assetId);
    try {
      final asset = _state.snapshot.assets.firstWhere(
        (asset) => asset.id == assetId,
      );
      final source = await assetStore.readBytes(asset.storageKey);
      if (isJobCancelled(id)) throw const _Cancelled();
      final converter = _imageThumbnail;
      if (converter == null) throw StateError('未装配图片缩略图实现');
      final thumbnail = await converter(source)
          .timeout(const Duration(seconds: 10));
      await storeThumbnail(assetId, thumbnail, jobId: id);
    } on _Cancelled {
      await finishCancelledThumbnail(id);
    } catch (error) {
      await failThumbnail(assetId, error.toString(), jobId: id);
    }
  }

  Future<void> retryJob(String id) async {
    _ensureOpen();
    final job = _job(id);
    if (!job.terminal) return;
    if (job.kind == JobKind.importFiles) {
      await importFiles(job.importKind ?? ImportKind.media);
      return;
    }
    final asset = _state.snapshot.assets.firstWhere(
      (asset) => asset.id == job.assetId,
    );
    if (asset.kind == MediaKind.video) throw StateError('请打开对应视频预览重试缩略图');
    await _generateImageThumbnail(asset.id);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    for (final cancellation in _cancellations.values) {
      cancellation.cancel();
    }
    // A system picker has no programmatic dismiss API. Its late result is
    // discarded before any storage access; do not block shutdown on that UI.
    if (!_selecting) await _importPending;
    await save();
    await _changes.close();
  }
}

final class _Cancellation {
  final _completion = Completer<void>();
  bool get cancelled => _completion.isCompleted;
  Future<void> get whenCancelled => _completion.future;
  void cancel() {
    if (!cancelled) _completion.complete();
  }

  void check() {
    if (cancelled) throw const _Cancelled();
  }
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

final class _CancellationRollbackFailed implements Exception {
  const _CancellationRollbackFailed(this.message);
  final String message;
  @override
  String toString() => '取消操作回滚保存失败，已保留可用内容：$message';
}
