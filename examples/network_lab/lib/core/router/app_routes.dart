import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:network_lab/features/network/presentation/screens/network_page.dart';
part 'app_routes.g.dart';

@TypedGoRoute<NetworkRoute>(path: '/')
class NetworkRoute extends GoRouteData with $NetworkRoute {
  const NetworkRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const NetworkPage();
}
