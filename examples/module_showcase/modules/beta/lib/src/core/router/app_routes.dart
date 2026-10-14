import 'package:showcase_beta/src/features/welcome/presentation/providers/beta_providers.dart';
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:showcase_beta/src/features/welcome/presentation/screens/beta_page.dart';

part 'app_routes.g.dart';

@Dependencies([betaMessage])
@TypedGoRoute<BetaRoute>(
  path: '/beta',
  routes: [TypedGoRoute<BetaDetailsRoute>(path: 'details')],
)
class BetaRoute extends GoRouteData with $BetaRoute {
  const BetaRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BetaPage(onOpenDetails: () => const BetaDetailsRoute().go(context));
}

@Dependencies([betaMessage])
class BetaDetailsRoute extends GoRouteData with $BetaDetailsRoute {
  const BetaDetailsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const BetaPage(details: true);
}
