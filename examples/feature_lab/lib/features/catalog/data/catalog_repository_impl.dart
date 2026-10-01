import 'package:feature_lab/features/catalog/data/catalog_data_source.dart';
import 'package:feature_lab/features/catalog/domain/catalog_item.dart';
import 'package:feature_lab/features/catalog/domain/catalog_repository.dart';
import 'package:koi_core/koi_core.dart';

final class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this.source);
  final CatalogDataSource source;

  @override
  FutureResult<List<CatalogItem>> load({required int page}) async {
    try {
      return success(await source.fetch(page: page));
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
