import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Bounded local history committed atomically with current task state. Products
/// needing long-term detail can provide another implementation of the port.
final class SnapshotJobHistoryRepository implements JobHistoryRepository {
  const SnapshotJobHistoryRepository(this.session);
  final WorkspaceSession session;

  @override
  Future<List<WorkspaceJob>> read({String? jobId, int limit = 50}) async =>
      session.readJobHistory(jobId: jobId, limit: limit);

  @override
  Future<void> clear() async {
    final result = await session.clearJobHistory();
    if (!result.succeeded) throw WorkspaceStorageException(result.error!);
  }
}
