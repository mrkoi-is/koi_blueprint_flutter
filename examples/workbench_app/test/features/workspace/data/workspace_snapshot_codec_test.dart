import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/workspace_snapshot_codec.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'fixtures/workspace_v1_fixture.dart';

void main() {
  const codec = WorkspaceSnapshotCodec();

  test('nonempty v1 migration preserves content without inventing history', () {
    final decoded = codec.decode(workspaceV1Fixture);
    final snapshot = decoded.snapshot;
    expect(decoded.sourceVersion, 1);
    expect(decoded.storageVersion, 7);
    expect(decoded.needsMigration, isTrue);
    expect(snapshot.schemaVersion, 2);
    expect(snapshot.revision, 42);
    expect(snapshot.documents.single.text, '保留正文');
    expect(snapshot.documents.single.dirty, isTrue);
    expect(snapshot.assets.single.storageKey, 'kept.png');
    expect(snapshot.todos.single.completed, isTrue);
    expect(snapshot.preferences.sidebarWidth, 312);
    expect(snapshot.jobs.map((job) => job.currentAttempt), everyElement(0));
    expect(snapshot.jobs.map((job) => job.startedAt), everyElement(isNull));
    expect(snapshot.jobs.map((job) => job.finishedAt), everyElement(isNull));
    expect(snapshot.jobs[1].status, JobStatus.running);
    expect(snapshot.jobHistory, isEmpty);
    final again = codec.decode(codec.encode(snapshot, storageVersion: 8));
    expect(again.snapshot, snapshot);
    expect(again.needsMigration, isFalse);
    expect(again.storageVersion, 8);
  });

  test(
    'unknown schema, invalid metadata and old-format writers fail explicitly',
    () {
      for (final schema in [0, 3, '2']) {
        expect(
          () => codec.decode(jsonEncode({'schemaVersion': schema})),
          throwsA(isA<UnsupportedWorkspaceVersion>()),
        );
      }
      expect(
        () => codec.decode('{broken'),
        throwsA(isA<WorkspaceStorageException>()),
      );
      expect(
        () => codec.decode('{"schemaVersion":2,"storageVersion":-1}'),
        throwsA(isA<WorkspaceStorageException>()),
      );
      expect(
        () => codec.encode(
          const WorkspaceSnapshot(schemaVersion: 1),
          storageVersion: 1,
        ),
        throwsA(isA<UnsupportedWorkspaceVersion>()),
      );
      expect(
        () => codec.encode(
          const WorkspaceSnapshot(
            jobs: [
              WorkspaceJob(
                id: 'j',
                kind: JobKind.importFiles,
                name: 'bad',
                currentAttempt: -1,
              ),
            ],
          ),
          storageVersion: 1,
        ),
        throwsA(isA<WorkspaceStorageException>()),
      );
    },
  );
}
