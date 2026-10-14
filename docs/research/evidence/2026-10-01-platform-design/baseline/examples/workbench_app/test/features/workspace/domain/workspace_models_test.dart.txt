import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

void main() {
  test('old persisted job without phase remains indeterminate', () {
    final job = WorkspaceJob.fromJson({
      'id': 'old',
      'kind': 'importFiles',
      'name': '导入',
    });
    expect(job.indeterminate, isTrue);
  });
  test(
    'snapshot round trip preserves Chinese, preferences and immutable values',
    () {
      const snapshot = WorkspaceSnapshot(
        revision: 4,
        documents: [
          WorkspaceDocument(
            id: 'd',
            title: '中文资料',
            text: '正文',
            revision: 2,
            savedRevision: 1,
          ),
        ],
        assets: [
          WorkspaceAsset(
            id: 'a',
            name: 'image.png',
            kind: MediaKind.image,
            byteLength: 42,
            storageKey: 'opaque',
          ),
        ],
        todos: [WorkspaceTodo(id: 't', title: '校验任务', completed: true)],
        jobs: [
          WorkspaceJob(
            id: 'j',
            kind: JobKind.importFiles,
            name: '导入',
            status: JobStatus.failed,
            importKind: ImportKind.text,
            error: '失败',
          ),
        ],
        preferences: WorkspacePreferences(
          themeMode: WorkspaceThemeMode.dark,
          density: WorkspaceDensity.compact,
          selectedDocumentId: 'd',
        ),
      );
      expect(
        WorkspaceSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>,
        ),
        snapshot,
      );
      expect(
        () => snapshot.documents.add(
          const WorkspaceDocument(id: 'b', title: 'B'),
        ),
        throwsUnsupportedError,
      );
      expect(snapshot.documents.single.dirty, isTrue);
      expect(
        snapshot.documents.single.copyWith(savedRevision: 2).dirty,
        isFalse,
      );
      expect(searchDocuments(snapshot.documents, '正文'), snapshot.documents);
      expect(searchDocuments(snapshot.documents, '找不到'), isEmpty);
      expect(searchDocuments(snapshot.documents, '  '), snapshot.documents);
    },
  );
  test('only settled task states are terminal', () {
    for (final status in JobStatus.values) {
      final job = WorkspaceJob(
        id: 'j',
        kind: JobKind.thumbnail,
        name: '缩略图',
        status: status,
      );
      expect(
        job.terminal,
        [
          JobStatus.succeeded,
          JobStatus.failed,
          JobStatus.cancelled,
          JobStatus.interrupted,
        ].contains(status),
      );
    }
  });
}
