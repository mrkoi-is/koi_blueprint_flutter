import 'package:feature_lab/features/catalog/domain/catalog_repository.dart';
import 'package:feature_lab/features/catalog/presentation/models/catalog_view_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_providers.g.dart';

@Riverpod(keepAlive: true)
CatalogRepository catalogRepository(Ref ref) =>
    throw UnimplementedError('Override catalogRepositoryProvider at bootstrap');

// Retained across route visits. Invalidate at account/module session boundaries.
@Riverpod(keepAlive: true)
class CatalogController extends _$CatalogController {
  int _page = 0;
  int _operation = 0;

  @override
  Future<CatalogViewState> build() async {
    _page = 0;
    ++_operation;
    final result = await ref.watch(catalogRepositoryProvider).load(page: 0);
    return result.fold(
      (error) => throw error,
      (items) => CatalogViewState(items: items),
    );
  }

  Future<void> refresh() async {
    if (state.isLoading && !state.hasValue) {
      // A command cannot safely race the Future returned by build: its later
      // completion would otherwise replace the command's newer result.
      ref.invalidateSelf();
      // The resulting AsyncError belongs in provider state, as with _load.
      await future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return;
    }
    await _load(0);
  }

  Future<void> loadMore() => state.hasValue ? _load(_page + 1) : Future.value();

  Future<void> _load(int page) async {
    final operation = ++_operation;
    final previous = state.value;
    state = previous == null
        ? const AsyncLoading()
        : AsyncData(
            previous.copyWith(isRefreshing: true, operationFailure: null),
          );
    final result = await ref.read(catalogRepositoryProvider).load(page: page);
    if (!ref.mounted || operation != _operation) return;
    state = result.fold(
      (error) => previous == null
          ? AsyncError(error, StackTrace.current)
          : AsyncData(
              previous.copyWith(isRefreshing: false, operationFailure: error),
            ),
      (items) {
        _page = page;
        return AsyncData(
          CatalogViewState(
            items: page == 0 ? items : [...?previous?.items, ...items],
          ),
        );
      },
    );
  }
}

@riverpod
AsyncValue<int> catalogCount(Ref ref) => ref
    .watch(catalogControllerProvider)
    .whenData((value) => value.items.length);
