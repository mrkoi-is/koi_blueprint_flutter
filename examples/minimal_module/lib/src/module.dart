import 'package:koi_modules/koi_modules.dart';
import 'package:minimal_module/src/core/router/app_routes.dart';

/// Replace Object with a public business capability when one is required.
KoiModule<Object> createMinimalModule() => KoiModule(
  id: 'minimal_module',
  routes: $appRoutes,
  navigation: [
    ModuleNavigationItem(
      id: 'minimal_module.home',
      label: 'Minimal Module',
      location: const MinimalModuleRoute().location,
    ),
  ],
  createSession: (_) => Object(),
);
