import 'dart:async';
import 'dart:developer' as developer;

import 'package:fpdart/fpdart.dart';
import 'package:koi_admin_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_core/koi_core.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.dataSource,
    required KoiTokenSession tokenSession,
  }) : tokenSession = tokenSession is KoiRevocableTokenSession
           ? tokenSession
           : KoiRevocableTokenSession(tokenSession);

  final AuthDataSource dataSource;
  final KoiRevocableTokenSession tokenSession;

  AuthLoginResult? _session;
  int _operation = 0;
  Future<void> _sessionMutation = Future<void>.value();

  @override
  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    final operation = ++_operation;

    if (companyCode.isBlank || username.isBlank || password.isBlank) {
      try {
        await _mutateSession(() async {
          if (operation != _operation) {
            return;
          }
          _session = null;
          await tokenSession.clearToken();
        });
      } catch (error, stackTrace) {
        return left(
          AppFailure.unknown(
            message: '登录失败，请稍后再试',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      return left(const AppFailure.validation(message: '公司编码、账号和密码不能为空'));
    }

    try {
      final shouldContinue = await _mutateSession(() async {
        if (operation != _operation) {
          return false;
        }
        _session = null;
        await tokenSession.clearToken();
        return operation == _operation;
      });
      if (!shouldContinue) {
        return left(_cancelledLoginFailure);
      }

      final result = await dataSource.login(
        companyCode: companyCode,
        username: username,
        password: password,
      );

      final committed = await _mutateSession(() async {
        if (operation != _operation) {
          return false;
        }

        try {
          await tokenSession.saveToken(result.token);
        } catch (_) {
          _session = null;
          try {
            await tokenSession.clearToken();
          } catch (_) {
            // 保留原始令牌写入错误，以便后续诊断。
          }
          rethrow;
        }

        if (operation != _operation ||
            tokenSession.getToken() != result.token) {
          _session = null;
          await tokenSession.clearToken();
          return false;
        }

        _session = result;
        return true;
      });
      if (!committed) {
        return left(_cancelledLoginFailure);
      }

      return right(result);
    } on InvalidCredentialsException catch (error) {
      return left(AppFailure.unauthorized(message: error.message));
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
  Future<void> logout() {
    ++_operation;
    return _mutateSession(() async {
      _session = null;
      await tokenSession.clearToken();
    });
  }

  @override
  AuthLoginResult? restoreSession() {
    final session = _session;
    if (session == null || tokenSession.getToken() != session.token) {
      _session = null;
      _revokeOrphanedToken();
      return null;
    }
    return session;
  }

  Future<T> _mutateSession<T>(Future<T> Function() mutation) {
    final completer = Completer<T>();
    _sessionMutation = _sessionMutation.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _revokeOrphanedToken() {
    try {
      unawaited(
        tokenSession.clearToken().catchError((Object error, StackTrace stack) {
          developer.log(
            'Failed to clear an orphaned authentication token',
            name: 'koi.auth',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to revoke an orphaned authentication token',
        name: 'koi.auth',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

const _cancelledLoginFailure = AppFailure.unknown(message: '登录操作已被取消');
