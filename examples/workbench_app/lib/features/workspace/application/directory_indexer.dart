import 'dart:async';

import 'package:workbench_app/features/workspace/domain/directory_index.dart';

/// One bounded scan. Cancellation closes enumeration and waits for accepted IO;
/// unobserved old entries survive a cancelled or failed scan.
final class DirectoryIndexRun {
  DirectoryIndexRun(
    DirectoryIndexSource source, {
    Map<String, IndexedFile> previous = const {},
    int concurrency = 4,
  }) : _source = source,
       _previous = Map.unmodifiable(previous),
       _concurrency = concurrency {
    if (concurrency < 1 || concurrency > 32) {
      throw ArgumentError.value(
        concurrency,
        'concurrency',
        'Must be between 1 and 32',
      );
    }
    result = _run();
  }

  final DirectoryIndexSource _source;
  final Map<String, IndexedFile> _previous;
  final int _concurrency;
  final _cancelled = Completer<void>();
  final _changes = StreamController<DirectoryIndexProgress>.broadcast();
  final _entries = <String, IndexedFile>{};
  final _issues = <DirectoryIndexIssue>[];
  final _seen = <String>{};
  int _visited = 0;
  int _inspected = 0;
  int _reused = 0;
  late final Future<DirectoryIndexResult> result;
  Stream<DirectoryIndexProgress> get changes => _changes.stream;
  bool get isCancelled => _cancelled.isCompleted;

  Future<void> cancel() async {
    if (!isCancelled) _cancelled.complete();
    await result;
  }

  DirectoryIndexProgress get progress => DirectoryIndexProgress(
    visited: _visited,
    inspected: _inspected,
    reused: _reused,
    failures: _issues.length,
  );

  Future<void> _inspect(DirectoryCandidate candidate) async {
    try {
      final fingerprint = await _source.fingerprint(candidate);
      if (isCancelled) return;
      final old = _previous[candidate.key];
      if (old != null && old.fingerprint.matches(fingerprint)) {
        _entries[candidate.key] = old;
        _reused++;
      } else {
        final entry = await _source.inspect(candidate, fingerprint);
        if (isCancelled) return;
        if (entry.key != candidate.key) throw StateError('索引返回了不同的文件键');
        _entries[candidate.key] = entry;
        _inspected++;
      }
    } catch (error) {
      if (isCancelled) return;
      _issues.add(
        DirectoryIndexIssue(key: candidate.key, message: error.toString()),
      );
      // Retain known content when one file is temporarily unreadable.
      final old = _previous[candidate.key];
      if (old != null) _entries[candidate.key] = old;
    } finally {
      // Bound notification volume independently of the size of the library.
      if (!isCancelled && (_inspected + _reused + _issues.length) % 32 == 0) {
        _changes.add(progress);
      }
    }
  }

  Future<DirectoryIndexResult> _run() async {
    final active = <Future<void>>{};
    StreamIterator<DirectoryCandidate>? iterator;
    var status = DirectoryIndexStatus.completed;
    try {
      iterator = StreamIterator(_source.enumerate());
      while (!isCancelled) {
        if (active.length >= _concurrency) {
          await Future.any<void>([...active, _cancelled.future]);
        }
        if (isCancelled) break;
        final hasNext = await Future.any<bool>([
          iterator.moveNext(),
          _cancelled.future.then((_) => false),
        ]);
        if (!hasNext || isCancelled) break;
        final candidate = iterator.current;
        if (!_seen.add(candidate.key)) continue;
        _visited++;
        late final Future<void> work;
        work = _inspect(candidate).whenComplete(() => active.remove(work));
        active.add(work);
      }
    } catch (error) {
      if (!isCancelled) {
        status = DirectoryIndexStatus.failed;
        _issues.add(DirectoryIndexIssue(message: error.toString()));
      }
    } finally {
      try {
        await iterator?.cancel();
      } catch (error) {
        status = DirectoryIndexStatus.failed;
        _issues.add(DirectoryIndexIssue(message: '关闭目录枚举失败：$error'));
      }
      await Future.wait(active);
    }
    if (isCancelled && status != DirectoryIndexStatus.failed) {
      status = DirectoryIndexStatus.cancelled;
    }
    final snapshot = DirectoryIndexResult(
      status: status,
      entries: status == DirectoryIndexStatus.completed
          ? _entries
          : {..._previous, ..._entries},
      issues: _issues,
      progress: progress,
    );
    _changes.add(snapshot.progress);
    // A paused UI subscriber must not delay completion or cancellation of IO.
    unawaited(_changes.close());
    return snapshot;
  }
}
