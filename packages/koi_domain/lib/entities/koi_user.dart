// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:koi_core/koi_core.dart';

part 'koi_user.freezed.dart';
part 'koi_user.g.dart';

@freezed
abstract class KoiUser with _$KoiUser {
  const KoiUser._();

  @JsonSerializable(
    checked: true,
    fieldRename: FieldRename.snake,
    explicitToJson: true,
  )
  const factory KoiUser({
    required String id,
    required String name,
    required String companyCode,
    required String role,
  }) = _KoiUser;

  factory KoiUser.fromJson(Map<String, dynamic> json) =>
      _$KoiUserFromJson(json);

  static Result<KoiUser> tryFromJson(Map<String, dynamic> json) {
    try {
      return success(KoiUser.fromJson(json));
    } catch (error, stackTrace) {
      return failure(
        AppFailure.serialization(error: error, stackTrace: stackTrace),
      );
    }
  }

  String get displayName => '$name · $role';
}
