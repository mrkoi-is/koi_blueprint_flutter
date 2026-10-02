import 'package:feature_lab/features/catalog/domain/catalog_item.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:koi_core/koi_core.dart';

part 'catalog_view_state.freezed.dart';

@freezed
abstract class CatalogViewState with _$CatalogViewState {
  const factory CatalogViewState({
    required List<CatalogItem> items,
    String? nextCursor,
    int? total,
    @Default(false) bool isRefreshing,
    @Default(false) bool isAppending,
    AppFailure? operationFailure,
  }) = _CatalogViewState;
}
