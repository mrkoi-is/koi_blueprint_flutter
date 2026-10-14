import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:minimal_module/src/features/home/presentation/screens/home_page.dart';

part 'app_routes.g.dart';

@TypedGoRoute<MinimalModuleRoute>(path: '/minimal_module')
class MinimalModuleRoute extends GoRouteData with $MinimalModuleRoute {
  const MinimalModuleRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const HomePage();
}
