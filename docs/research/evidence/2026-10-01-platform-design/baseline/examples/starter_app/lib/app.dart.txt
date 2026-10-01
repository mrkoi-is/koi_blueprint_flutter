import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:starter_app/core/router/app_routes.dart';

class StarterApp extends StatefulWidget {
  const StarterApp({super.key});

  @override
  State<StarterApp> createState() => _StarterAppState();
}

class _StarterAppState extends State<StarterApp> {
  late final GoRouter _router = GoRouter(routes: $appRoutes);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Starter App',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    routerConfig: _router,
  );
}
