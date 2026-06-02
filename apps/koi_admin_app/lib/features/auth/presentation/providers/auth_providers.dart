import 'package:koi_admin_app/core/providers/bootstrap_providers.dart';
import 'package:koi_admin_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:koi_admin_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_auth/koi_auth.dart';
import 'package:koi_domain/koi_domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

@riverpod
MockAuthDataSource authDataSource(Ref ref) => MockAuthDataSource();

@riverpod
AuthRepository authRepository(Ref ref) {
  return AuthRepositoryImpl(
    dataSource: ref.watch(authDataSourceProvider),
    sharedPreferences: ref.watch(sharedPreferencesProvider),
  );
}

@riverpod
class AuthController extends _$AuthController {
  @override
  AuthSession<KoiUser> build() {
    final session = ref.watch(authRepositoryProvider).restoreSession();
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
    state = const AuthSession.loading();

    final result = await ref
        .read(authRepositoryProvider)
        .login(
          companyCode: companyCode,
          username: username,
          password: password,
        );

    state = result.match(
      (failure) => AuthSession.failure(message: failure.displayMessage),
      (session) =>
          AuthSession.authenticated(user: session.user, token: session.token),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthSession.unauthenticated();
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
