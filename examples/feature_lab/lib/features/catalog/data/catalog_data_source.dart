import 'package:feature_lab/features/catalog/domain/catalog_item.dart';

/// Implement at bootstrap using your generated API + Koi request executor.
/// Wire DTO conversion here; generated API and transport types stay out of UI.
abstract interface class CatalogDataSource {
  Future<List<CatalogItem>> fetch({required int page});
}
