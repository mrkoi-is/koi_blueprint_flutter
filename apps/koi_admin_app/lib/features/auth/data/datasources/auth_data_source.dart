import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';

abstract interface class AuthDataSource {
  Future<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  });
}

final class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException(this.message);

  final String message;
}
