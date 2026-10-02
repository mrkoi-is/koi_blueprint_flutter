import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage_web.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

import 'progress_driver.dart';

import 'package:workbench_app/features/workspace/presentation/models/text_view_state.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/screens/text_page.dart';
import 'package:workbench_app/features/workspace/presentation/screens/tasks_page.dart';
import 'package:workbench_app/l10n/app_strings.dart';

var stateBuilds = 0;
var documentBuilds = 0;
final phases = <Map<String, Object?>>[];
final probeClock = Stopwatch();
void phase(String label, [Map<String, Object?> values = const {}]) =>
    phases.add({
      'label': label,
      'ms': probeClock.elapsedMicroseconds / 1000,
      'performanceNowMs': web.window.performance.now(),
      ...values,
    });
String get probeView => Uri.base.queryParameters['view'] ?? 'both';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final name = 'koi_browser_perf_${DateTime.now().microsecondsSinceEpoch}';
  final storage = await openStorage(webDatabaseName: name);
  final repository = _Repository(storage.repository);
  final source = _Source();
  final session = WorkspaceSession(
    repository: repository,
    assetStore: storage.assetStore,
    fileImportPort: _Picker(source),
  );
  final frames = <FrameTiming>[];
  final raf = <double>[];
  int? rafHandle;
  final callback = ((num time) {
    raf.add(time.toDouble());
  }).toJS;
  void schedule() {
    rafHandle = web.window.requestAnimationFrame(
      ((num time) {
        callback.callAsFunction(null, time.toJS);
        schedule();
      }).toJS,
    );
  }

  void timing(List<FrameTiming> values) => frames.addAll(values);
  final container = ProviderContainer(
    overrides: [workspaceSessionProvider.overrideWithValue(session)],
  );
  Map<String, Object?>? report;
  try {
    await storage.repository.save(
      WorkspaceSnapshot(
        documents: List.generate(
          10000,
          (i) => WorkspaceDocument(
            id: 'doc_$i',
            title: 'Document $i',
            text: List.filled(256, 'x').join(),
          ),
        ),
      ),
      expectedVersion: 0,
    );
    await session.initialize();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: _Probe()),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    stateBuilds = 0;
    documentBuilds = 0;
    phases.clear();
    probeClock.start();
    phase('import-start');
    SchedulerBinding.instance.addTimingsCallback(timing);
    schedule();
    var events = 0;
    final subscription = session.changes.listen((_) {
      events++;
    });
    final clock = Stopwatch()..start();
    await session.importFiles(ImportKind.text);
    phase('import-returned');
    await session.save();
    phase('explicit-save-returned');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subscription.cancel();
    SchedulerBinding.instance.removeTimingsCallback(timing);
    if (rafHandle != null) web.window.cancelAnimationFrame(rafHandle!);
    final intervals = [
      for (var i = 1; i < raf.length; i++) raf[i] - raf[i - 1],
    ];
    report = {
      'status': 'passed',
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'runtime': 'Flutter Web release CanvasKit in real headless Chrome; TextPage and TasksPage; IndexedDB + Web Locks',
      'documents': 10000,
      'viewport': {
        'width': web.window.innerWidth,
        'height': web.window.innerHeight,
        'devicePixelRatio': web.window.devicePixelRatio,
      },
      'scenario': {
        'driver': source.driver.mode,
        'view': probeView,
        'content': source.driver.lineBreaks ? 'lines' : 'unbroken',
      },
      'driver': source.driver.metrics,
      'phases': List<Map<String, Object?>>.of(phases),
      'requestedHz': 200,
      'chunks': source.chunks,
      'sourceElapsedMs': source.elapsedUs / 1000,
      'achievedSourceHz': source.chunks / (source.elapsedUs / 1000000),
      'totalMs': clock.elapsedMicroseconds / 1000,
      'stateEvents': events,
      'stateProbeBuilds': stateBuilds,
      'documentSelectorProbeBuilds': documentBuilds,
      'snapshotCommits': repository.writes,
      'frameTimings': {
        'samples': frames.length,
        'largestBuildFrames':
            (frames.toList()
                  ..sort((a, b) => b.buildDuration.compareTo(a.buildDuration)))
                .take(5)
                .map(
                  (frame) => {
                    'frameNumber': frame.frameNumber,
                    'buildStartUs': frame.timestampInMicroseconds(
                      FramePhase.buildStart,
                    ),
                    'buildMs': frame.buildDuration.inMicroseconds / 1000,
                    'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
                  },
                )
                .toList(),
        'buildMs': stats(
          frames
              .map((frame) => frame.buildDuration.inMicroseconds / 1000)
              .toList(),
        ),
        'rasterMs': stats(
          frames
              .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
              .toList(),
        ),
      },
      'requestAnimationFrameIntervalMs': stats(intervals),
      'measurementNotes': [
        'Probe build counts are dedicated Riverpod consumers, not a count of every widget.',
        'requestAnimationFrame intervals are browser scheduling, not Flutter raster time.',
        'Zero FrameTiming samples means this renderer did not report Flutter timings.',
      ],
    };
  } catch (error, stack) {
    report = {'status': 'failed', 'error': '$error', 'stack': '$stack'};
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(timing);
    if (rafHandle != null) web.window.cancelAnimationFrame(rafHandle!);
    runApp(const SizedBox());
    await SchedulerBinding.instance.endOfFrame;
    container.dispose();
    await session.dispose();
    await storage.close();
    final request = web.window.indexedDB.deleteDatabase(name);
    final deleted = Completer<void>();
    request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
    request.onerror = ((web.Event _) => deleted.completeError(
      StateError('Benchmark cleanup failed'),
    )).toJS;
    await deleted.future;
  }
  web.document.documentElement!.setAttribute(
    'data-test-result',
    jsonEncode(report),
  );
}

Map<String, Object?> stats(List<double> values) {
  if (values.isEmpty) return {'status': 'NOT_REPORTED'};
  values.sort();
  return {
    'samples': values.length,
    'p50': values[values.length ~/ 2],
    'p95': values[((values.length - 1) * .95).floor()],
    'max': values.last,
  };
}

class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(workspaceStateProvider);
    stateBuilds++;
    if (probeView == 'tasks') return const TasksPage();
    return const Row(
      children: [
        Expanded(child: _DocumentProbe()),
        Expanded(child: TasksPage()),
      ],
    );
  }
}

class _DocumentProbe extends ConsumerWidget {
  const _DocumentProbe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(workspaceSessionProvider);
    ref.watch(
      workspaceStateProvider.select(
        (value) => TextViewState(
          documents:
              value.value?.snapshot.documents ??
              session.state.snapshot.documents,
          selectedId: value.value?.snapshot.preferences.selectedDocumentId,
          sidebarWidth: 0,
        ),
      ),
    );
    documentBuilds++;
    final state = session.state.snapshot;
    phase('document-view-build', {
      'selectedCharacters':
          state.documents
              .where((doc) => doc.id == state.preferences.selectedDocumentId)
              .firstOrNull
              ?.text
              .length ??
          state.documents.firstOrNull?.text.length,
    });
    return const TextPage();
  }
}

final class _Repository implements WorkspaceRepository {
  _Repository(this.inner);
  final WorkspaceRepository inner;
  int writes = 0;
  @override
  int get persistedVersion => inner.persistedVersion;
  @override
  Future<WorkspaceSnapshot> load() => inner.load();
  @override
  Future<void> save(WorkspaceSnapshot snapshot, {int? expectedVersion}) async {
    phase('snapshot-save-start', {'write': writes + 1});
    await inner.save(snapshot, expectedVersion: expectedVersion);
    writes++;
    phase('snapshot-save-finished', {'write': writes});
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
    mode: Uri.base.queryParameters['driver'] ?? 'deadline',
    lineBreaks: Uri.base.queryParameters['content'] == 'lines',
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
  Future<void> close() async {
    phase('source-closed');
  }
}
