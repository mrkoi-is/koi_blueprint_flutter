import 'package:go_router/go_router.dart';
import 'package:koi_admin_app/core/router/app_routes.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: const SplashRoute().location,
    routes: $appRoutes,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final onSplash = location == const SplashRoute().location;
      final onLogin = location == const LoginRoute().location;
      final isAuthenticated = authState.isAuthenticated;

      if (onSplash) {
        return null;
      }
      if (!isAuthenticated && !onLogin) {
        return const LoginRoute().location;
      }
      if (isAuthenticated && onLogin) {
        return const DashboardRoute().location;
      }
      return null;
    },
  );
}
