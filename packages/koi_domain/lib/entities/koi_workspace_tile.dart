// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:koi_core/koi_core.dart';

part 'koi_workspace_tile.freezed.dart';
part 'koi_workspace_tile.g.dart';

@Freezed(toStringOverride: false)
abstract class KoiWorkspaceTile with _$KoiWorkspaceTile {
  @JsonSerializable(checked: true)
  const factory KoiWorkspaceTile({
    required String title,
    required String description,
    required String category,
    @Default(false) bool highlighted,
  }) = _KoiWorkspaceTile;

  factory KoiWorkspaceTile.fromJson(Map<String, dynamic> json) =>
      _$KoiWorkspaceTileFromJson(json);

  static Result<KoiWorkspaceTile> tryFromJson(Map<String, dynamic> json) {
    try {
      return success(KoiWorkspaceTile.fromJson(json));
    } catch (error, stackTrace) {
      return failure(
        AppFailure.serialization(error: error, stackTrace: stackTrace),
      );
    }
  }
}
