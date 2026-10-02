import 'package:feature_lab/features/catalog/domain/catalog_item.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_page_slice.freezed.dart';

/// Null nextCursor is authoritative: an empty or short page alone is not a
/// reliable end-of-list signal. Cursor values are opaque to presentation.
@freezed
abstract class CatalogPageSlice with _$CatalogPageSlice {
  const factory CatalogPageSlice({
    required List<CatalogItem> items,
    String? nextCursor,
    int? total,
  }) = _CatalogPageSlice;
}
