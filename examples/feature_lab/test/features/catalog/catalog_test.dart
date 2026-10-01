import 'dart:async';

import 'package:feature_lab/features/catalog/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

class Source implements CatalogDataSource {
  Object? error;
  @override
  Future<List<CatalogItem>> fetch({required int page}) async {
    if (error != null) throw error!;
    return [CatalogItem(id: '$page', label: 'Item $page')];
  }
}

class Repository implements CatalogRepository {
  final pending = <Completer<Result<List<CatalogItem>>>>[];
  @override
  FutureResult<List<CatalogItem>> load({required int page}) {
    final request = Completer<Result<List<CatalogItem>>>();
    pending.add(request);
    return request.future;
  }
}

void main() {
  test(
    'repository preserves typed failures and maps unexpected transport errors',
    () async {
      final source = Source();
      final repository = CatalogRepositoryImpl(source);
      expect((await repository.load(page: 0)).getOrElse((_) => []), [
        const CatalogItem(id: '0', label: 'Item 0'),
      ]);
      expect(CatalogItem.fromJson({'id': '0', 'label': 'Item 0'}).toJson(), {
        'id': '0',
        'label': 'Item 0',
      });
      source.error = const AppFailure.network(message: 'offline');
      expect((await repository.load(page: 0)).isLeft(), isTrue);
      source.error = StateError('bad DTO');
      expect((await repository.load(page: 0)).isLeft(), isTrue);
    },
  );

  test('retains route state, preserves data on refresh/pagination failure, rejects stale replies', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(catalogControllerProvider, (_, _) {});
    repository.pending[0].complete(
      success([const CatalogItem(id: 'a', label: 'A')]),
    );
    await container.read(catalogControllerProvider.future);
    expect(container.read(catalogCountProvider).requireValue, 1);
    sub.close();
    await container.pump();
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'a',
    );
    final notifier = container.read(catalogControllerProvider.notifier);
    final refresh = notifier.refresh();
    repository.pending[1].complete(
      failure(const AppFailure.network(message: 'offline')),
    );
    await refresh;
    expect(
      container.read(catalogControllerProvider).requireValue.operationFailure,
      isNotNull,
    );
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'a',
    );
    final more = notifier.loadMore();
    repository.pending[2].complete(
      failure(const AppFailure.network(message: 'offline')),
    );
    await more;
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'a',
    );
    final next = notifier.loadMore();
    repository.pending[3].complete(
      success([const CatalogItem(id: 'b', label: 'B')]),
    );
    await next;
    expect(
      container.read(catalogControllerProvider).requireValue.items.length,
      2,
    );
    final older = notifier.refresh();
    final newer = notifier.refresh();
    repository.pending[5].complete(
      success([const CatalogItem(id: 'new', label: 'New')]),
    );
    await newer;
    repository.pending[4].complete(
      success([const CatalogItem(id: 'old', label: 'Old')]),
    );
    await older;
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'new',
    );
  });

  test('initial response cannot replace a newer refresh', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    final refresh = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    repository.pending[1].complete(
      success([const CatalogItem(id: 'new', label: 'New')]),
    );
    await refresh;
    repository.pending[0].complete(
      success([const CatalogItem(id: 'old', label: 'Old')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'new',
    );
  });

  test(
    'load more before initial data does not start a second request',
    () async {
      final repository = Repository();
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.listen(catalogControllerProvider, (_, _) {});
      await container.read(catalogControllerProvider.notifier).loadMore();
      expect(repository.pending, hasLength(1));
      repository.pending.single.complete(success(const []));
      expect(
        (await container.read(catalogControllerProvider.future)).items,
        isEmpty,
      );
    },
  );

  test('late request after provider disposal cannot write state', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
    );
    container.listen(catalogControllerProvider, (_, _) {});
    repository.pending.single.complete(
      success([const CatalogItem(id: 'a', label: 'A')]),
    );
    await container.read(catalogControllerProvider.future);
    final pending = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    container.dispose();
    repository.pending[1].complete(
      success([const CatalogItem(id: 'late', label: 'Late')]),
    );
    await pending;
  });

  test('initial failure cannot replace a newer successful refresh', () async {
    final repository = Repository();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(catalogControllerProvider, (_, _) {});
    final refresh = container
        .read(catalogControllerProvider.notifier)
        .refresh();
    repository.pending[1].complete(
      success([const CatalogItem(id: 'new', label: 'New')]),
    );
    await refresh;
    repository.pending[0].complete(
      failure(const AppFailure.network(message: 'old failure')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(catalogControllerProvider).requireValue.items.single.id,
      'new',
    );
  });

  test(
    'new initial refresh failure remains an error after old success',
    () async {
      final repository = Repository();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.listen(catalogControllerProvider, (_, _) {});
      final refresh = container
          .read(catalogControllerProvider.notifier)
          .refresh();
      repository.pending[1].complete(
        failure(const AppFailure.network(message: 'new failure')),
      );
      await refresh;
      repository.pending[0].complete(
        success([const CatalogItem(id: 'old', label: 'Old')]),
      );
      await Future<void>.delayed(Duration.zero);
      final state = container.read(catalogControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<AppFailure>());
      expect(state.hasValue, isFalse);
    },
  );

  testWidgets(
    'initial failure is not empty; refresh failure keeps rendered items',
    (tester) async {
      final source = Source()
        ..error = const AppFailure.network(message: 'offline');
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
      source.error = const AppFailure.network(message: 'offline');
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Unable to load catalog'), findsOneWidget);
    },
  );
}
