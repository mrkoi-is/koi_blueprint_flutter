import 'package:showcase_alpha/src/features/welcome/presentation/providers/alpha_providers.dart';
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:showcase_alpha/src/features/welcome/presentation/screens/alpha_page.dart';

part 'app_routes.g.dart';

@Dependencies([alphaMessage])
@TypedGoRoute<AlphaRoute>(
  path: '/alpha',
  routes: [TypedGoRoute<AlphaDetailsRoute>(path: 'details')],
)
class AlphaRoute extends GoRouteData with $AlphaRoute {
  const AlphaRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      AlphaPage(onOpenDetails: () => const AlphaDetailsRoute().go(context));
}

@Dependencies([alphaMessage])
class AlphaDetailsRoute extends GoRouteData with $AlphaDetailsRoute {
  const AlphaDetailsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AlphaPage(details: true);
}
