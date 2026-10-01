import 'package:feature_lab/features/catalog/domain/catalog_item.dart';
import 'package:koi_core/koi_core.dart';

abstract interface class CatalogRepository {
  FutureResult<List<CatalogItem>> load({required int page});
}
