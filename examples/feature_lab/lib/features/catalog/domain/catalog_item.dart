import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_item.freezed.dart';
part 'catalog_item.g.dart';

@freezed
abstract class CatalogItem with _$CatalogItem {
  const factory CatalogItem({required String id, required String label}) =
      _CatalogItem;
  factory CatalogItem.fromJson(Map<String, dynamic> json) =>
      _$CatalogItemFromJson(json);
}
