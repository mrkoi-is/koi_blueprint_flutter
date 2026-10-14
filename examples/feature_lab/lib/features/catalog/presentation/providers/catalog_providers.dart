import 'dart:async';

import 'package:feature_lab/features/catalog/domain/catalog_item.dart';
import 'package:feature_lab/features/catalog/domain/catalog_page_slice.dart';
import 'package:feature_lab/features/catalog/domain/catalog_repository.dart';
import 'package:feature_lab/features/catalog/domain/catalog_request.dart';
import 'package:feature_lab/features/catalog/presentation/models/catalog_view_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_providers.g.dart';

@Riverpod(keepAlive: true)
CatalogRepository catalogRepository(Ref ref) =>
    throw UnimplementedError('Override catalogRepositoryProvider at bootstrap');

@Riverpod(keepAlive: true)
class CatalogQuery extends _$CatalogQuery {
  Timer? _debounce;
  @override
  String build() {
    ref.onDispose(() => _debounce?.cancel());
    return '';
  }

  void setQuery(
    String query, {
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _debounce?.cancel();
    if (debounce == Duration.zero) {
      state = query.trim();
    } else {
      _debounce = Timer(debounce, () {
        if (ref.mounted) state = query.trim();
      });
    }
  }
}

// Retained across route visits. Invalidate query and controller when the host
// account/module session changes. The repository owns its bounded TTL cache.
@Riverpod(keepAlive: true)
class CatalogController extends _$CatalogController {
  int _operation = 0;
  CatalogCancellation? _cancellation;
  Future<void>? _append;
  String _query = '';

  @override
  Future<CatalogViewState> build() async {
    _query = ref.watch(catalogQueryProvider);
    ++_operation;
    _append = null;
    _cancellation?.cancel();
    final cancellation = _cancellation = CatalogCancellation();
    ref.onDispose(() => _cancellation?.cancel());
    final result = await ref
        .watch(catalogRepositoryProvider)
        .load(query: _query, cancellation: cancellation);
    return result.fold((error) => throw error, (page) => _view(page));
  }

  Future<void> refresh() async {
    if (state.isLoading && !state.hasValue) {
      ref.invalidateSelf();
      await future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return;
    }
    _append = null;
    await _load(null, append: false);
  }

  Future<void> loadMore() {
    final previous = state.value;
    if (previous == null ||
        previous.isRefreshing ||
        previous.nextCursor == null) {
      return Future.value();
    }
    final existing = _append;
    if (existing != null) return existing;
    final operation = _load(previous.nextCursor, append: true);
    _append = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_append, operation)) _append = null;
      }),
    );
    return operation;
  }

  CatalogViewState _view(
    CatalogPageSlice page, [
    List<CatalogItem> before = const [],
  ]) {
    final items = <String, CatalogItem>{
      for (final item in before) item.id: item,
    };
    for (final item in page.items) {
      items[item.id] = item;
    }
    return CatalogViewState(
      items: items.values.toList(),
      nextCursor: page.nextCursor,
      total: page.total,
    );
  }

  Future<void> _load(String? cursor, {required bool append}) async {
    final operation = ++_operation;
    _cancellation?.cancel();
    final cancellation = _cancellation = CatalogCancellation();
    final previous = state.value;
    state = previous == null
        ? const AsyncLoading()
        : AsyncData(
            previous.copyWith(
              isRefreshing: !append,
              isAppending: append,
              operationFailure: null,
            ),
          );
    final result = await ref
        .read(catalogRepositoryProvider)
        .load(
          query: _query,
          cursor: cursor,
          cancellation: cancellation,
          refresh: !append,
        );
    if (!ref.mounted || operation != _operation) return;
    state = result.fold(
      (error) => previous == null
          ? AsyncError(error, StackTrace.current)
          : AsyncData(
              previous.copyWith(
                isRefreshing: false,
                isAppending: false,
                operationFailure: error,
              ),
            ),
      (page) => AsyncData(_view(page, append ? previous!.items : const [])),
    );
  }
}

@riverpod
AsyncValue<int> catalogCount(Ref ref) => ref
    .watch(catalogControllerProvider)
    .whenData((value) => value.items.length);
