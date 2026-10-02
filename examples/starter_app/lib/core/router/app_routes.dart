import 'package:starter_app/core/capabilities/capability_page.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:starter_app/features/home/presentation/screens/home_page.dart';

part 'app_routes.g.dart';

@TypedGoRoute<HomeRoute>(path: '/')
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const HomePage();
}

@TypedGoRoute<CapabilityRoute>(path: '/capabilities/:id')
class CapabilityRoute extends GoRouteData with $CapabilityRoute {
  const CapabilityRoute({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      CapabilityPage(id: id);
}
