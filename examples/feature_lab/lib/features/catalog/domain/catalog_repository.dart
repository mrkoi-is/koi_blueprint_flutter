import 'package:feature_lab/features/catalog/domain/catalog_page_slice.dart';
import 'package:feature_lab/features/catalog/domain/catalog_request.dart';
import 'package:koi_core/koi_core.dart';

abstract interface class CatalogRepository {
  FutureResult<CatalogPageSlice> load({
    required CatalogCancellation cancellation,
    String query = '',
    String? cursor,
    bool refresh = false,
  });
}
