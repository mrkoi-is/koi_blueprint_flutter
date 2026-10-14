import 'dart:convert';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Shared Native/Web format boundary. IO, locking and CAS belong to storage.
final class WorkspaceSnapshotCodec {
  const WorkspaceSnapshotCodec();

  static const currentVersion = 2;

  DecodedWorkspaceSnapshot decode(String contents) {
    try {
      final raw = jsonDecode(contents) as Map<String, dynamic>;
      final schema = raw['schemaVersion'] ?? 1;
      if (schema is! int || schema < 1 || schema > currentVersion) {
        throw const UnsupportedWorkspaceVersion();
      }
      final storageVersion = raw['storageVersion'] ?? 0;
      if (storageVersion is! int || storageVersion < 0) {
        throw const WorkspaceStorageException('无效持久化版本');
      }
      final migrated = schema == 1 ? _fromV1(raw) : raw;
      final snapshot = WorkspaceSnapshot.fromJson(migrated);
      for (final job in [...snapshot.jobs, ...snapshot.jobHistory]) {
        if (job.currentAttempt < 0 ||
            (job.startedAt != null &&
                job.finishedAt != null &&
                job.finishedAt!.isBefore(job.startedAt!))) {
          throw const WorkspaceStorageException('无效任务执行记录');
        }
      }
      return DecodedWorkspaceSnapshot(
        snapshot: snapshot,
        sourceVersion: schema,
        storageVersion: storageVersion,
      );
    } on WorkspaceStorageException {
      rethrow;
    } catch (error) {
      throw WorkspaceStorageException('工作区快照损坏：$error');
    }
  }

  String encode(WorkspaceSnapshot snapshot, {required int storageVersion}) {
    if (snapshot.schemaVersion != currentVersion) {
      throw const UnsupportedWorkspaceVersion();
    }
    final contents = jsonEncode({
      ...snapshot.toJson(),
      'storageVersion': storageVersion,
    });
    // Invalid callers cannot persist data that the next open cannot read.
    decode(contents);
    return contents;
  }

  Map<String, dynamic> _fromV1(Map<String, dynamic> raw) => {
    ...raw,
    'schemaVersion': currentVersion,
    'jobs': [
      for (final job in (raw['jobs'] as List<dynamic>? ?? const []))
        {
          ...job as Map<String, dynamic>,
          'currentAttempt': 0,
          'startedAt': null,
          'finishedAt': null,
        },
    ],
    'jobHistory': <dynamic>[],
  };
}

final class DecodedWorkspaceSnapshot {
  const DecodedWorkspaceSnapshot({
    required this.snapshot,
    required this.sourceVersion,
    required this.storageVersion,
  });
  final WorkspaceSnapshot snapshot;
  final int sourceVersion;
  final int storageVersion;
  bool get needsMigration =>
      sourceVersion != WorkspaceSnapshotCodec.currentVersion;
}

final class UnsupportedWorkspaceVersion extends WorkspaceStorageException {
  const UnsupportedWorkspaceVersion() : super('无法读取此工作区版本');
}
