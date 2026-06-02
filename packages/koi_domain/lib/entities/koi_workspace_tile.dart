// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'koi_workspace_tile.freezed.dart';
part 'koi_workspace_tile.g.dart';

@freezed
abstract class KoiWorkspaceTile with _$KoiWorkspaceTile {
  const factory KoiWorkspaceTile({
    required String title,
    required String description,
    required String category,
    @Default(false) bool highlighted,
  }) = _KoiWorkspaceTile;

  factory KoiWorkspaceTile.fromJson(Map<String, dynamic> json) =>
      _$KoiWorkspaceTileFromJson(json);
}
