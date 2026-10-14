import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_admin_app/core/router/app_routes.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refreshListenable = _RouterRefreshListenable();

  ref
    ..listen(authControllerProvider, (_, _) => refreshListenable.refresh())
    ..onDispose(refreshListenable.dispose);

  final router = GoRouter(
    initialLocation: const SplashRoute().location,
    routes: $appRoutes,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
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

  ref.onDispose(router.dispose);
  return router;
}

final class _RouterRefreshListenable extends ChangeNotifier {
  void refresh() => notifyListeners();
}
