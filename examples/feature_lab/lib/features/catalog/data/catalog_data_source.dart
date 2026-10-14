import 'package:feature_lab/features/catalog/domain/catalog_page_slice.dart';
import 'package:feature_lab/features/catalog/domain/catalog_request.dart';

/// Implement at bootstrap using your generated API + request executor.
/// Wire cancellation to the actual transport. Transport and DTO types stay here.
abstract interface class CatalogDataSource {
  Future<CatalogPageSlice> fetch({
    required CatalogCancellation cancellation,
    String query = '',
    String? cursor,
  });
}
