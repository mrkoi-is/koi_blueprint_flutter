import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/directory_indexer.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';

final _modified = DateTime.utc(2026, 10, 2);
IndexedFile _entry(String key, {int size = 1}) => IndexedFile(
  key: key,
  name: key,
  fingerprint: DirectoryFingerprint(byteLength: size, modifiedAt: _modified),
  fileType: 'txt',
);

final class _Source implements DirectoryIndexSource {
  _Source(this.count);
  final int count;
  final changed = <String>{};
  final broken = <String>{};
  int reads = 0;
  int active = 0;
  int maxActive = 0;
  Completer<void>? gate;
  final entered = Completer<void>();
  Stream<DirectoryCandidate>? stream;
  @override
  Stream<DirectoryCandidate> enumerate() =>
      stream ??
      Stream.fromIterable(
        List.generate(
          count,
          (i) => DirectoryCandidate(key: '$i', name: '$i.txt'),
        ),
      );
  @override
  Future<DirectoryFingerprint> fingerprint(
    DirectoryCandidate candidate,
  ) async => DirectoryFingerprint(
    byteLength: changed.contains(candidate.key) ? 2 : 1,
    modifiedAt: _modified,
  );
  @override
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  ) async {
    reads++;
    active++;
    if (active > maxActive) maxActive = active;
    if (!entered.isCompleted) entered.complete();
    try {
      await (gate?.future ?? Future<void>.delayed(Duration.zero));
      if (broken.contains(candidate.key)) throw StateError('unreadable');
      return IndexedFile(
        key: candidate.key,
        name: candidate.name,
        fingerprint: fingerprint,
        fileType: 'txt',
      );
    } finally {
      active--;
    }
  }
}

void main() {
  test('10000 entries use bounded concurrency and only changed files are reinspected', () async {
    final source = _Source(10000);
    final run = DirectoryIndexRun(source, concurrency: 4);
    var notifications = 0;
    final sub = run.changes.listen((_) => notifications++);
    final first = await run.result;
    expect(first.status, DirectoryIndexStatus.completed);
    expect(first.entries, hasLength(10000));
    expect(source.maxActive, lessThanOrEqualTo(4));
    expect(source.reads, 10000);
    expect(notifications, lessThan(320));
    source.changed.add('5');
    final second = await DirectoryIndexRun(
      source,
      previous: {...first.entries, 'removed': _entry('removed')},
    ).result;
    expect(source.reads, 10001);
    expect(second.progress.reused, 9999);
    expect(second.entries.containsKey('removed'), isFalse);
    expect(second.entries['5']!.fingerprint.byteLength, 2);
    await sub.cancel();
  });

  test(
    'one unreadable file retains its prior entry and reports a visible issue',
    () async {
      final source = _Source(3)
        ..broken.add('1')
        ..changed.add('1');
      final previous = {'1': _entry('1')};
      final result = await DirectoryIndexRun(source, previous: previous).result;
      expect(result.status, DirectoryIndexStatus.completed);
      expect(result.entries, hasLength(3));
      expect(result.entries['1'], same(previous['1']));
      expect(result.issues.single.key, '1');
    },
  );

  test('cancel closes enumeration immediately, drains owned IO and keeps unobserved old entries', () async {
    final cancelled = Completer<void>();
    final stream = StreamController<DirectoryCandidate>(
      onCancel: cancelled.complete,
    );
    final source = _Source(0)
      ..stream = stream.stream
      ..gate = Completer<void>();
    final run = DirectoryIndexRun(
      source,
      previous: {'old': _entry('old')},
      concurrency: 1,
    );
    stream.add(const DirectoryCandidate(key: 'new', name: 'new'));
    await source.entered.future;
    var finished = false;
    final stopping = run.cancel().then((_) => finished = true);
    await cancelled.future;
    expect(finished, isFalse);
    source.gate!.complete();
    await stopping;
    final result = await run.result;
    expect(result.status, DirectoryIndexStatus.cancelled);
    expect(result.entries.keys, ['old']);
    expect(source.active, 0);
    await run.cancel();
    await stream.close();
  });

  test('enumeration failure preserves previous data and invalid concurrency is rejected', () async {
    final source = _Source(0)
      ..stream = Stream.error(StateError('directory removed'));
    final result = await DirectoryIndexRun(
      source,
      previous: {'old': _entry('old')},
    ).result;
    expect(result.status, DirectoryIndexStatus.failed);
    expect(result.entries.keys, ['old']);
    expect(result.issues.single.message, contains('directory removed'));
    expect(
      () => DirectoryIndexRun(source, concurrency: 0),
      throwsArgumentError,
    );
  });
}
