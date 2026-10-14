import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_core/koi_core.dart';

abstract class AuthRepository {
  AuthLoginResult? restoreSession();

  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  });

  Future<void> logout();
}
