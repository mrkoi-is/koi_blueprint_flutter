import 'package:feature_lab/features/catalog/data/catalog_data_source.dart';
import 'package:feature_lab/features/catalog/domain/catalog_page_slice.dart';
import 'package:feature_lab/features/catalog/domain/catalog_request.dart';
import 'package:feature_lab/features/catalog/domain/catalog_repository.dart';
import 'package:koi_core/koi_core.dart';

final class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(
    this.source, {
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 128,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (ttl <= Duration.zero || maxEntries < 1) {
      throw ArgumentError('Invalid catalog cache limits');
    }
  }
  final CatalogDataSource source;
  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  // Repository lifetime is the account/module scope; entries never cross owners.
  final _cache =
      <(String, String?), ({CatalogPageSlice page, DateTime expires})>{};
  void clearCache() => _cache.clear();

  @override
  FutureResult<CatalogPageSlice> load({
    required CatalogCancellation cancellation,
    String query = '',
    String? cursor,
    bool refresh = false,
  }) async {
    final key = (query, cursor);
    final cached = _cache.remove(key);
    if (!refresh &&
        !cancellation.isCancelled &&
        cached != null &&
        _now().isBefore(cached.expires)) {
      _cache[key] = cached;
      return success(cached.page);
    }
    try {
      if (cancellation.isCancelled) {
        return failure(const AppFailure.network(message: 'Cancelled'));
      }
      final page = await source.fetch(
        cancellation: cancellation,
        query: query,
        cursor: cursor,
      );
      if (cursor != null && page.nextCursor == cursor) {
        throw StateError('Cursor did not advance');
      }
      if (!cancellation.isCancelled) {
        while (_cache.length >= maxEntries) {
          _cache.remove(_cache.keys.first);
        }
        _cache[key] = (page: page, expires: _now().add(ttl));
      }
      return success(page);
    } on AppFailure catch (error) {
      return failure(error);
    } catch (error, stackTrace) {
      return failure(
        AppFailure.unknown(
          message: 'Unable to load catalog',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
