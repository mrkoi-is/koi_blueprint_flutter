import 'package:fpdart/fpdart.dart';
import 'package:koi_admin_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required MockAuthDataSource dataSource,
    required SharedPreferences sharedPreferences,
  }) : _dataSource = dataSource,
       _sharedPreferences = sharedPreferences;

  static const _tokenKey = 'auth_token';
  static const _userNameKey = 'auth_user_name';
  static const _companyCodeKey = 'auth_company_code';

  final MockAuthDataSource _dataSource;
  final SharedPreferences _sharedPreferences;

  @override
  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    if (companyCode.isBlank || username.isBlank || password.isBlank) {
      return left(const AppFailure.validation(message: '公司编码、账号和密码不能为空'));
    }

    if (password != '123456') {
      return left(const AppFailure.unauthorized(message: '示例密码固定为 123456'));
    }

    try {
      final result = await _dataSource.login(
        companyCode: companyCode,
        username: username,
      );

      await _sharedPreferences.setString(_tokenKey, result.token);
      await _sharedPreferences.setString(_userNameKey, result.user.name);
      await _sharedPreferences.setString(
        _companyCodeKey,
        result.user.companyCode,
      );

      return right(result);
    } catch (error, stackTrace) {
      return left(
        AppFailure.unknown(
          message: '登录失败，请稍后再试',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> logout() async {
    await _sharedPreferences.remove(_tokenKey);
    await _sharedPreferences.remove(_userNameKey);
    await _sharedPreferences.remove(_companyCodeKey);
  }

  @override
  AuthLoginResult? restoreSession() {
    final token = _sharedPreferences.getString(_tokenKey);
    final username = _sharedPreferences.getString(_userNameKey);
    final companyCode = _sharedPreferences.getString(_companyCodeKey);

    if (token == null || username == null || companyCode == null) {
      return null;
    }

    return AuthLoginResult(
      user: KoiUser(
        id: 'cached_$username',
        name: username,
        companyCode: companyCode,
        role: 'operator',
      ),
      token: token,
    );
  }
}
