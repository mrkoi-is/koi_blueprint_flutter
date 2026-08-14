import 'dart:developer' as developer;

import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_auth/koi_auth.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  throw UnimplementedError(
    '请在 bootstrap.dart 或测试中 override authRepositoryProvider',
  );
}

@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  int _operation = 0;

  @override
  AuthSession<KoiUser> build() {
    final session = ref.read(authRepositoryProvider).restoreSession();
    if (session == null) {
      return const AuthSession.unauthenticated();
    }
    return AuthSession.authenticated(user: session.user, token: session.token);
  }

  Future<void> login({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    final operation = ++_operation;
    state = const AuthSession.loading();

    final result = await ref
        .read(authRepositoryProvider)
        .login(
          companyCode: companyCode,
          username: username,
          password: password,
        );

    if (operation != _operation) {
      return;
    }

    result.match(
      (failure) {
        _reportFailure(failure);
        state = AuthSession.failure(message: failure.displayMessage);
      },
      (session) {
        state = AuthSession.authenticated(
          user: session.user,
          token: session.token,
        );
      },
    );
  }

  Future<void> logout() async {
    final operation = ++_operation;
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to clear the authentication session',
        name: 'koi.auth',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (operation == _operation) {
        state = const AuthSession.unauthenticated();
      }
    }
  }

  Future<void> handleUnauthorized() => logout();

  void _reportFailure(AppFailure failure) {
    if (failure case UnknownFailure(:final error, :final stackTrace)) {
      developer.log(
        'Authentication operation failed',
        name: 'koi.auth',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

@riverpod
bool isAuthenticated(Ref ref) =>
    ref.watch(authControllerProvider).isAuthenticated;

@riverpod
KoiUser? currentUser(Ref ref) {
  return ref
      .watch(authControllerProvider)
      .maybeWhen(authenticated: (user, _) => user, orElse: () => null);
}
