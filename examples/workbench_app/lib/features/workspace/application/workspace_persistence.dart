import 'dart:async';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'package:workbench_app/features/workspace/application/internal/workspace_workflow_access.dart';

/// Serializes durable writes. The queued operation captures the session at
/// execution time; its acknowledgement only marks the captured document revisions.
final class WorkspacePersistence {
  WorkspacePersistence({
    required this._access,
    required this._repository,
    required this._debounce,
    required this._beforeSave,
  });
  final WorkspaceWorkflowAccess _access;
  final WorkspaceRepository _repository;
  final Duration _debounce;
  final void Function() _beforeSave;
  Future<void> _savePending = Future.value();
  int _persistedVersion = 0;
  Timer? _timer;
  WorkspaceState get _state => _access.state;

  Future<WorkspaceSnapshot> load() async {
    final snapshot = await _repository.load();
    _persistedVersion = _repository.persistedVersion;
    return snapshot;
  }

  void scheduleSave() {
    cancelScheduledSave();
    _timer = Timer(_debounce, () => unawaited(save()));
  }

  void cancelScheduledSave() {
    _timer?.cancel();
    _timer = null;
  }

  Future<WorkspaceSaveResult> save() {
    _beforeSave();
    cancelScheduledSave();
    final operation = _savePending.then((_) async {
      if (!_state.initialized) {
        return const WorkspaceSaveResult.failed('工作区尚未初始化');
      }
      final captured = _state.snapshot;
      final persisted = captured.copyWith(
        documents: captured.documents
            .map(
              (document) => document.copyWith(savedRevision: document.revision),
            )
            .toList(),
      );
      _access.updateState((state) => state.copyWith(saving: true, error: null));
      try {
        await _repository.save(persisted, expectedVersion: _persistedVersion);
        _persistedVersion = _repository.persistedVersion;
        final revisions = {
          for (final document in captured.documents)
            document.id: document.revision,
        };
        _access.updateState(
          (state) => state.copyWith(
            saving: false,
            snapshot: state.snapshot.copyWith(
              documents: state.snapshot.documents
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
        return WorkspaceSaveResult.saved(captured.revision);
      } catch (error) {
        final message = '保存失败：$error';
        _access.updateState(
          (state) => state.copyWith(saving: false, error: message),
        );
        return WorkspaceSaveResult.failed(message);
      }
    });
    _savePending = operation.then((_) {});
    return operation;
  }
}
