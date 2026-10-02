import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/application/network_session.dart';
import 'package:network_lab/features/network/application/reachability_monitor.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';

class Search implements SearchRepository {
  final calls =
      <
        ({
          String query,
          String? cursor,
          Cancellation cancellation,
          Completer<NetworkPage> result,
        })
      >[];
  bool cleared = false;
  @override
  Future<NetworkPage> search(
    String query, {
    String? cursor,
    required Cancellation cancellation,
    bool refresh = false,
  }) {
    final value = (
      query: query,
      cursor: cursor,
      cancellation: cancellation,
      result: Completer<NetworkPage>(),
    );
    calls.add(value);
    return value.result.future;
  }

  @override
  void clear() {
    cleared = true;
  }
}

NetworkPage page(List<String> ids, {String? next}) => NetworkPage(
  items: ids.map((id) => NetworkEntry(id: id, label: id)).toList(),
  nextCursor: next,
);
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));
void main() {
  test('successful query history is recent-first, unique, bounded to 20 and optional', () async {
    final repository = Search();
    final transport = FakeTransport(
      (u, m, h, c) =>
          HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
    );
    NetworkSession create({int historyLimit = 20}) => NetworkSession(
      repository: repository,
      transfers: TransferEngine(transport, MemoryTransferStore()),
      transport: transport,
      baseUri: Uri.parse('http://fixture/'),
      historyLimit: historyLimit,
    );
    final session = create();
    Future<void> search(
      NetworkSession owner,
      String query, {
      bool fail = false,
    }) async {
      owner.search(query);
      final pending = owner.refresh();
      if (fail) {
        repository.calls.last.result.completeError(StateError('offline'));
      } else {
        repository.calls.last.result.complete(page([query]));
      }
      await pending;
    }

    for (var index = 0; index < 25; index++) {
      await search(session, 'q$index');
    }
    expect(
      session.snapshot.history,
      List.generate(20, (index) => 'q${24 - index}'),
    );
    await search(session, ' q7 ');
    expect(session.snapshot.history.first, 'q7');
    expect(
      session.snapshot.history.where((value) => value == 'q7'),
      hasLength(1),
    );
    expect(session.snapshot.history, hasLength(20));
    await search(session, 'failed', fail: true);
    expect(session.snapshot.history, isNot(contains('failed')));
    await session.close();
    final disabled = create(historyLimit: 0);
    await search(disabled, 'not-recorded');
    expect(disabled.snapshot.history, isEmpty);
    await disabled.close();
    expect(() => create(historyLimit: -1), throwsArgumentError);
  });
  test('download coalesces; cancel settles after cleanup; retry creates a new attempt', () async {
    var mode = 'wait';
    final repository = Search();
    final store = MemoryTransferStore();
    final transport = FakeTransport((u, m, h, c) {
      if (m == 'HEAD') {
        return HttpPayload(
          status: mode == 'fail' ? 503 : 200,
          headers: {'content-length': '2'},
          body: const Stream.empty(),
        );
      }
      Stream<List<int>> body() async* {
        yield [1];
        if (mode == 'wait') {
          final stopped = Completer<void>();
          final detach = c.onCancel(() => stopped.complete());
          await stopped.future;
          detach();
          c.check();
        }
        yield [2];
      }

      return HttpPayload(status: 200, headers: {}, body: body());
    });
    final session = NetworkSession(
      repository: repository,
      transfers: TransferEngine(transport, store),
      transport: transport,
      baseUri: Uri.parse('http://fixture/'),
    );
    final pending = session.download();
    expect(identical(pending, session.download()), true);
    await tick();
    final cancelling = session.cancelDownload();
    expect(session.snapshot.transfer.phase, TransferPhase.cancelling);
    await cancelling;
    expect(session.snapshot.transfer.phase, TransferPhase.cancelled);
    expect(store.stages, isEmpty);
    await session.cancelDownload();
    mode = 'fail';
    await session.download();
    expect(session.snapshot.transfer.phase, TransferPhase.failed);
    mode = 'ok';
    await session.download();
    expect(session.snapshot.transfer.phase, TransferPhase.complete);
    expect(store.completed['fixture_download'], [1, 2]);
    await session.close();
    await session.download();
    await session.loadMore();
  });
  test('debounce, query cancellation, stale result, pagination merging and final page', () async {
    final repository = Search();
    final transport = FakeTransport(
      (u, m, h, c) =>
          HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
    );
    final session = NetworkSession(
      repository: repository,
      transfers: TransferEngine(transport, MemoryTransferStore()),
      transport: transport,
      baseUri: Uri.parse('http://fixture/'),
      debounce: const Duration(milliseconds: 2),
    );
    session.search('discarded');
    session.search('one');
    await tick();
    expect(repository.calls, hasLength(1));
    session.search(' two ');
    expect(repository.calls.first.cancellation.isCancelled, true);
    await tick();
    repository.calls.last.result.complete(page(['a'], next: 'n'));
    await tick();
    repository.calls.first.result.complete(page(['stale']));
    await tick();
    expect(session.snapshot.items.single.id, 'a');
    final more = session.loadMore();
    expect(identical(more, session.loadMore()), true);
    expect(repository.calls.last.cursor, 'n');
    repository.calls.last.result.complete(page(['a', 'b']));
    await more;
    expect(session.snapshot.items.map((item) => item.id), ['a', 'b']);
    await session.loadMore();
    expect(repository.calls, hasLength(3));
    expect(session.snapshot.history, ['two']);
    final refresh = session.refresh();
    repository.calls.last.result.completeError(StateError('offline'));
    await refresh;
    expect(session.snapshot.error, contains('offline'));
    expect(session.snapshot.items, hasLength(2));
    session.search('');
    await tick();
    expect(session.snapshot.items, isEmpty);
    expect(repository.calls, hasLength(4));
    session.clearCache();
    expect(repository.cleared, true);
    await session.close();
    await session.close();
  });
  test('refresh supersedes append, close awaits current queries and clears scoped cache', () async {
    final repo = Search();
    final transport = FakeTransport(
      (u, m, h, c) =>
          HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
    );
    final session = NetworkSession(
      repository: repo,
      transfers: TransferEngine(transport, MemoryTransferStore()),
      transport: transport,
      baseUri: Uri.parse('http://fixture/'),
      debounce: Duration.zero,
    );
    session.search('q');
    await tick();
    repo.calls.last.result.complete(page(['a'], next: 'n'));
    await tick();
    final more = session.loadMore();
    final refresh = session.refresh();
    expect(repo.calls[1].cancellation.isCancelled, true);
    repo.calls[2].result.complete(page(['new']));
    await refresh;
    repo.calls[1].result.complete(page(['old']));
    await more;
    expect(session.snapshot.items.single.id, 'new');
    final query = session.refresh();
    final closing = session.close();
    expect(repo.calls.last.cancellation.isCancelled, true);
    repo.calls.last.result.complete(page(['late']));
    await query;
    await closing;
    expect(repo.cleared, true);
    session.search('ignored');
    expect(session.snapshot.items.single.id, 'new');
  });
  test(
    'reachability pause cancels active probe; late results cannot publish',
    () async {
      final pending = <Completer<HttpPayload>>[];
      final signals = <Cancellation>[];
      final transport = FakeTransport((u, m, h, c) {
        signals.add(c);
        final result = Completer<HttpPayload>();
        pending.add(result);
        return result.future;
      });
      final states = <Reachability>[];
      final monitor = ReachabilityMonitor(
        transport,
        Uri.parse('http://fixture/health'),
        states.add,
        interval: const Duration(hours: 1),
      );
      monitor.setActive(true);
      expect(pending, hasLength(1));
      monitor.setActive(false);
      expect(signals.single.isCancelled, true);
      pending.single.complete(
        HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
      );
      await tick();
      expect(states, isEmpty);
      monitor.setActive(true);
      pending.last.complete(
        HttpPayload(status: 503, headers: {}, body: const Stream.empty()),
      );
      await tick();
      expect(states, [Reachability.unreachable]);
      final retry = monitor.probe();
      pending.last.complete(
        HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
      );
      await retry;
      expect(states.last, Reachability.reachable);
      monitor.close();
      monitor.setActive(true);
      expect(pending, hasLength(3));
    },
  );
}
