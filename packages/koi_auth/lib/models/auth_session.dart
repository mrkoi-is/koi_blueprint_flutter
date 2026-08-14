import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_session.freezed.dart';

@Freezed(toStringOverride: false)
sealed class AuthSession<TUser> with _$AuthSession<TUser> {
  const AuthSession._();

  const factory AuthSession.unauthenticated() = AuthUnauthenticated<TUser>;

  const factory AuthSession.loading() = AuthLoading<TUser>;

  const factory AuthSession.authenticated({
    required TUser user,
    required String token,
  }) = AuthAuthenticated<TUser>;

  const factory AuthSession.failure({required String message}) =
      AuthFailureState<TUser>;

  bool get isAuthenticated =>
      maybeWhen(authenticated: (user, token) => true, orElse: () => false);
}
