import 'package:flutter/widgets.dart';
import 'package:koi_admin_app/core/router/app_routes.dart';

extension AppNavigation on BuildContext {
  void goToLogin() => const LoginRoute().go(this);

  void goToDashboard() => const DashboardRoute().go(this);

  void goToSettings() => const SettingsRoute().go(this);
}
