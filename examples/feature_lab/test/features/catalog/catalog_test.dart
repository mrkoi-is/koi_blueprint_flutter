import 'dart:async';

import 'package:feature_lab/features/catalog/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

CatalogPageSlice page(List<String> ids, {String? next}) => CatalogPageSlice(
  items: ids.map((id) => CatalogItem(id: id, label: 'Item $id')).toList(),
  nextCursor: next,
  total: 10,
);

class Source implements CatalogDataSource {
  Object? error;
  int calls = 0;
  @override
  Future<CatalogPageSlice> fetch({
    required CatalogCancellation cancellation,
    String query = '',
    String? cursor,
  }) async {
    calls++;
    if (error != null) throw error!;
    return page([cursor ?? '0'], next: cursor == null ? '1' : null);
  }
}

class Request {
  Request(this.cancellation, this.query, this.cursor);
  final CatalogCancellation cancellation;
  final String query;
  final String? cursor;
  final result = Completer<Result<CatalogPageSlice>>();
  void complete(CatalogPageSlice value) => result.complete(success(value));
  void fail() =>
      result.complete(failure(const AppFailure.network(message: 'offline')));
}

class Repository implements CatalogRepository {
  final pending = <Request>[];
  @override
  FutureResult<CatalogPageSlice> load({
    required CatalogCancellation cancellation,
    String query = '',
    String? cursor,
    bool refresh = false,
  }) {
    final request = Request(cancellation, query, cursor);
    pending.add(request);
    return request.result.future;
  }
}

ProviderContainer containerFor(Repository repository) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
);
void main() {
  test(
    'repository TTL boundary, bounded eviction, refresh and cancellation',
    () async {
      var now = DateTime.utc(2026);
      final source = Source();
      final repo = CatalogRepositoryImpl(source, now: () => now, maxEntries: 1);
      Future<Result<CatalogPageSlice>> load(
        String query, {
        bool refresh = false,
      }) => repo.load(
        query: query,
        cancellation: CatalogCancellation(),
        refresh: refresh,
      );
      await load('a');
      await load('a');
      expect(source.calls, 1);
      now = now.add(
        const Duration(minutes: 5) - const Duration(milliseconds: 1),
      );
      await load('a');
      expect(source.calls, 1);
      now = now.add(const Duration(milliseconds: 1));
      await load('a');
      expect(source.calls, 2);
      await load('b');
      await load('a');
      expect(source.calls, 4);
      await load('a', refresh: true);
      expect(source.calls, 5);
      repo.clearCache();
      await load('a');
      expect(source.calls, 6);
      final cancelled = CatalogCancellation()..cancel();
      expect(
        (await repo.load(query: 'a', cancellation: cancelled)).isLeft(),
        true,
      );
      expect(source.calls, 6);
    },
  );

  test(
    'repository maps errors and keeps cursor/total/model semantics',
    () async {
      final source = Source();
      final repository = CatalogRepositoryImpl(source);
      final cancellation = CatalogCancellation();
      expect(
        (await repository.load(cancellation: cancellation))
            .getOrElse((_) => page([]))
            .nextCursor,
        '1',
      );
      expect(CatalogItem.fromJson({'id': 'a', 'label': 'A'}).toJson(), {
        'id': 'a',
        'label': 'A',
      });
      source.error = const AppFailure.network(message: 'offline');
      expect(
        (await repository.load(
          cancellation: cancellation,
          refresh: true,
        )).isLeft(),
        true,
      );
      source.error = StateError('DTO');
      expect(
        (await repository.load(
          cancellation: cancellation,
          refresh: true,
        )).isLeft(),
        true,
      );
    },
  );
  test(
    'same cursor coalesces, stable IDs deduplicate, final page stops requests',
    () async {
      final repo = Repository();
      final container = containerFor(repo);
      addTearDown(container.dispose);
      final sub = container.listen(catalogControllerProvider, (_, _) {});
      repo.pending.single.complete(page(['a', 'b'], next: 'opaque-1'));
      await container.read(catalogControllerProvider.future);
      sub.close();
      await container.pump();
      expect(container.read(catalogCountProvider).requireValue, 2);
      final notifier = container.read(catalogControllerProvider.notifier);
      final first = notifier.loadMore();
      final repeated = notifier.loadMore();
      expect(identical(first, repeated), true);
      expect(repo.pending, hasLength(2));
      expect(repo.pending.last.cursor, 'opaque-1');
      expect(
        container.read(catalogControllerProvider).requireValue.isAppending,
        true,
      );
      repo.pending.last.complete(page(['b', 'c']));
      await first;
      expect(
        container
            .read(catalogControllerProvider)
            .requireValue
            .items
            .map((item) => item.id),
        ['a', 'b', 'c'],
      );
      await notifier.loadMore();
      expect(repo.pending, hasLength(2));
    },
  );
  test('refresh cancels append, rejects stale reply and preserves old content on error', () async {
    final repo = Repository();
    final container = containerFor(repo);
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    repo.pending.single.complete(page(['a'], next: 'next'));
    await container.read(catalogControllerProvider.future);
    final notifier = container.read(catalogControllerProvider.notifier);
    final more = notifier.loadMore();
    final refresh = notifier.refresh();
    expect(repo.pending[1].cancellation.isCancelled, true);
    repo.pending[2].complete(page(['new']));
    await refresh;
    repo.pending[1].complete(page(['stale']));
    await more;
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'new',
    );
    final failing = notifier.refresh();
    repo.pending.last.fail();
    await failing;
    final value = container.read(catalogControllerProvider).requireValue;
    expect(value.items.single.id, 'new');
    expect(value.operationFailure, isNotNull);
    expect(value.isRefreshing, false);
  });
  test('append failure retries the same opaque cursor', () async {
    final repo = Repository();
    final container = containerFor(repo);
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    repo.pending.single.complete(page(['a'], next: 'next'));
    await container.read(catalogControllerProvider.future);
    final notifier = container.read(catalogControllerProvider.notifier);
    final failed = notifier.loadMore();
    repo.pending.last.fail();
    await failed;
    final retry = notifier.loadMore();
    expect(repo.pending.last.cursor, 'next');
    repo.pending.last.complete(page(['b']));
    await retry;
    expect(
      container.read(catalogControllerProvider).requireValue.items,
      hasLength(2),
    );
  });
  test('initial refresh cancels first request and late success cannot replace error', () async {
    final repo = Repository();
    final container = containerFor(repo);
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    await container.read(catalogControllerProvider.notifier).loadMore();
    expect(repo.pending, hasLength(1));
    final refresh = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    expect(repo.pending.first.cancellation.isCancelled, true);
    repo.pending[1].fail();
    await refresh;
    repo.pending.first.complete(page(['old']));
    await container.pump();
    expect(container.read(catalogControllerProvider).hasError, true);
  });
  test('initial late failure cannot replace refreshed success', () async {
    final repo = Repository();
    final container = containerFor(repo);
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    final refresh = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    repo.pending[1].complete(page(['new']));
    await refresh;
    repo.pending.first.fail();
    await container.pump();
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'new',
    );
  });
  test(
    'query debounce replaces pending input, changes cancel old transport',
    () async {
      final repo = Repository();
      final container = containerFor(repo);
      addTearDown(container.dispose);
      container.listen(catalogControllerProvider, (_, _) {});
      final query = container.read(catalogQueryProvider.notifier);
      query.setQuery('old', debounce: const Duration(milliseconds: 10));
      query.setQuery(' final ', debounce: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.pump();
      expect(repo.pending, hasLength(2));
      expect(repo.pending.last.query, 'final');
      expect(repo.pending.first.cancellation.isCancelled, true);
      repo.pending.last.complete(page(['final']));
      await container.read(catalogControllerProvider.future);
      repo.pending.first.complete(page(['old']));
      await container.pump();
      expect(
        container.read(catalogControllerProvider).requireValue.items.single.id,
        'final',
      );
      query.setQuery('', debounce: Duration.zero);
      await container.pump();
      repo.pending.last.complete(page([]));
      expect(
        (await container.read(catalogControllerProvider.future)).items,
        isEmpty,
      );
    },
  );
  test(
    'disposing owner cancels latest command and rejects its late result',
    () async {
      final repo = Repository();
      final container = containerFor(repo);
      container.listen(catalogControllerProvider, (_, _) {});
      repo.pending.single.complete(page(['a']));
      await container.read(catalogControllerProvider.future);
      final refresh = container
          .read(catalogControllerProvider.notifier)
          .refresh();
      container.dispose();
      expect(repo.pending.last.cancellation.isCancelled, true);
      repo.pending.last.complete(page(['late']));
      await refresh;
    },
  );
  test('cancellation is idempotent and listeners can detach', () async {
    final signal = CatalogCancellation();
    var calls = 0;
    final detach = signal.onCancel(() => calls++);
    detach();
    signal.onCancel(() => calls++);
    signal.cancel();
    signal.cancel();
    await signal.cancelled;
    signal.onCancel(() => calls++);
    expect(calls, 2);
  });
  testWidgets('error is distinct from empty and last page disables append', (
    tester,
  ) async {
    final source = Source()..error = StateError('offline');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepositoryImpl(source),
          ),
        ],
        child: const MaterialApp(home: CatalogPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load catalog'), findsOneWidget);
    expect(find.text('No items'), findsNothing);
    source.error = null;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Item 0'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Item 1'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Load more'))
          .onPressed,
      isNull,
    );
  });
}
