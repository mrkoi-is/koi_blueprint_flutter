import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/directory_indexer.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/data/native_directory_index_source.dart';
import 'package:workbench_app/features/workspace/data/workspace_snapshot_codec.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_native.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'progress_driver.dart';

void main() {
  test(
    'actual Native 10k snapshot/index and nominal 200 Hz progress benchmark',
    () async {
      final root = await Directory.systemTemp.createTemp('koi-workspace-perf-');
      final initialRss = ProcessInfo.currentRss;
      var peakRss = initialRss;
      final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
      });
      final storage = NativeWorkspaceStorage('${root.path}/workspace');
      WorkspaceSession? session;
      try {
        final snapshot = WorkspaceSnapshot(
          revision: 1,
          documents: List.generate(
            10000,
            (i) => WorkspaceDocument(
              id: 'doc_$i',
              title: 'Document $i',
              text: List.filled(256, 'x').join(),
            ),
          ),
        );
        final watch = Stopwatch()..start();
        final encoded = const WorkspaceSnapshotCodec().encode(
          snapshot,
          storageVersion: 1,
        );
        final encodeUs = watch.elapsedMicroseconds;
        watch.reset();
        const WorkspaceSnapshotCodec().decode(encoded);
        final decodeUs = watch.elapsedMicroseconds;
        await storage.initialize();
        watch.reset();
        await storage.save(snapshot, expectedVersion: 0);
        final firstWriteUs = watch.elapsedMicroseconds;
        watch.reset();
        final loaded = await storage.load();
        final loadUs = watch.elapsedMicroseconds;
        expect(loaded.documents.length, 10000);
        final repository = _CountingRepository(
          storage,
          File('${root.path}/workspace/workspace.json'),
          legacyReencode: const bool.fromEnvironment('PERF_LEGACY_REENCODE'),
        );
        final input = _Source();
        session = WorkspaceSession(
          repository: repository,
          assetStore: storage,
          fileImportPort: _Picker(input),
        );
        await session.initialize();
        var stateEvents = 0;
        var progressEvents = 0;
        final subscription = session.changes.listen((state) {
          stateEvents++;
          if (state.snapshot.jobs.any(
            (job) => job.status == JobStatus.running,
          )) {
            progressEvents++;
          }
        });
        watch.reset();
        await session.importFiles(ImportKind.text);
        await session.save();
        final importUs = watch.elapsedMicroseconds;
        await subscription.cancel();
        expect(session.state.snapshot.jobs.single.status, JobStatus.succeeded);
        expect(repository.writes, lessThan(15));
        final directory = await Directory('${root.path}/files').create();
        for (var start = 0; start < 10000; start += 32) {
          await Future.wait([
            for (var i = start; i < start + 32 && i < 10000; i++)
              File('${directory.path}/file_$i.txt')
                  .writeAsString('document $i'),
          ]);
        }
        final source = NativeDirectoryIndexSource(directory.path);
        watch.reset();
        final first = await DirectoryIndexRun(source).result;
        final firstIndexUs = watch.elapsedMicroseconds;
        watch.reset();
        final second = await DirectoryIndexRun(
          source,
          previous: first.entries,
        ).result;
        final secondIndexUs = watch.elapsedMicroseconds;
        expect(first.entries.length, 10000);
        expect(second.progress.reused, 10000);
        expect(second.issues, isEmpty);
        final report = <String, Object?>{
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
          'runtime': 'Flutter test Dart VM, real filesystem and wall clock',
          'os': Platform.operatingSystemVersion,
          'dart': Platform.version,
          'documents': 10000,
          'bodyCharactersPerDocument': 256,
          'snapshotBytes': utf8.encode(encoded).length,
          'encodeMs': encodeUs / 1000,
          'decodeMs': decodeUs / 1000,
          'initialAtomicWriteMs': firstWriteUs / 1000,
          'loadMs': loadUs / 1000,
          'measurementMode': repository.legacyReencode
              ? 'Legacy second serialization for byte counting'
              : 'Async stat of committed snapshot; no second serialization',
          'progress': {
            'driver': input.driver.metrics,
            'requestedHz': 200,
            'chunks': input.chunks,
            'sourceElapsedMs': input.elapsedUs / 1000,
            'achievedSourceHz': input.chunks / (input.elapsedUs / 1000000),
            'importElapsedMs': importUs / 1000,
            'sessionStateEvents': stateEvents,
            'runningStateEvents': progressEvents,
            'snapshotCommits': repository.writes,
            'serializedSnapshotBytesWritten': repository.bytes,
          },
          'index': {
            'files': 10000,
            'concurrency': 4,
            'initialMs': firstIndexUs / 1000,
            'repeatMs': secondIndexUs / 1000,
            'reused': second.progress.reused,
          },
          'rss': {
            'beforeBytes': initialRss,
            'afterBytes': ProcessInfo.currentRss,
            'sampledPeakBytes': peakRss,
            'sampleIntervalMs': 20,
          },
          'uiFrameTime': 'NOT_MEASURED_IN_VM',
          'uiRebuilds': 'NOT_MEASURED_IN_VM',
        };
        final output = File('build/perf/workspace-native.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        // ignore: avoid_print
        print(jsonEncode(report));
      } finally {
        sampler.cancel();
        await session?.dispose();
        await storage.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _CountingRepository implements WorkspaceRepository {
  _CountingRepository(
    this.storage,
    this.snapshotFile, {
    required this.legacyReencode,
  });
  final NativeWorkspaceStorage storage;
  final File snapshotFile;
  final bool legacyReencode;
  int writes = 0;
  int bytes = 0;
  @override
  int get persistedVersion => storage.persistedVersion;
  @override
  Future<WorkspaceSnapshot> load() => storage.load();
  @override
  Future<void> save(WorkspaceSnapshot snapshot, {int? expectedVersion}) async {
    await storage.save(snapshot, expectedVersion: expectedVersion);
    writes++;
    bytes += legacyReencode
        ? utf8
              .encode(
                const WorkspaceSnapshotCodec().encode(
                  snapshot,
                  storageVersion: 1,
                ),
              )
              .length
        : await snapshotFile.length();
  }
}

final class _Picker implements FileImportPort {
  _Picker(this.source);
  final _Source source;
  @override
  Future<FileImportResult> select(ImportKind kind) async =>
      FilesSelected([source]);
}

final class _Source implements ImportSource {
  final driver = ProgressDriver(
    mode: const String.fromEnvironment('PERF_DRIVER', defaultValue: 'deadline'),
  );
  int get chunks => driver.deliveredAtUs.length;
  int get elapsedUs => driver.deliveredAtUs.last;
  @override
  String get name => 'benchmark.txt';
  @override
  int get byteLength => driver.chunks * driver.chunkBytes;
  @override
  Stream<List<int>> openRead() => driver.open();
  @override
  Future<void> close() async {}
}
