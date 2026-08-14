import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:koi_domain/koi_domain.dart';

part 'auth_login_result.freezed.dart';

@Freezed(toStringOverride: false)
abstract class AuthLoginResult with _$AuthLoginResult {
  const factory AuthLoginResult({
    required KoiUser user,
    required String token,
  }) = _AuthLoginResult;
}
