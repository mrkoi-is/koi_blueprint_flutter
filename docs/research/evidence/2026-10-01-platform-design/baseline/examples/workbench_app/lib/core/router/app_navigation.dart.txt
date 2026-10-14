import 'package:flutter/widgets.dart';
import 'package:workbench_app/core/router/app_routes.dart';

extension WorkbenchNavigation on BuildContext {
  void goToText() => const TextRoute().go(this);
  void goToMedia() => const MediaRoute().go(this);
  void goToTasks() => const TasksRoute().go(this);
}
