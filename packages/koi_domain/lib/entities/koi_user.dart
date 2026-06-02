// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'koi_user.freezed.dart';
part 'koi_user.g.dart';

@freezed
abstract class KoiUser with _$KoiUser {
  const KoiUser._();

  @JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
  const factory KoiUser({
    required String id,
    required String name,
    required String companyCode,
    required String role,
  }) = _KoiUser;

  factory KoiUser.fromJson(Map<String, dynamic> json) =>
      _$KoiUserFromJson(json);

  String get displayName => '$name · $role';
}
