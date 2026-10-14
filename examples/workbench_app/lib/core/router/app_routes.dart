import 'package:workbench_app/core/capabilities/capability_page.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:workbench_app/features/workspace/presentation/screens/media_page.dart';
import 'package:workbench_app/features/workspace/presentation/screens/tasks_page.dart';
import 'package:workbench_app/features/workspace/presentation/screens/text_page.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_shell.dart';

part 'app_routes.g.dart';

@TypedStatefulShellRoute<WorkbenchShellRoute>(
  branches: [
    TypedStatefulShellBranch<TextBranch>(
      routes: [TypedGoRoute<TextRoute>(path: '/text')],
    ),
    TypedStatefulShellBranch<MediaBranch>(
      routes: [TypedGoRoute<MediaRoute>(path: '/media')],
    ),
    TypedStatefulShellBranch<TasksBranch>(
      routes: [TypedGoRoute<TasksRoute>(path: '/tasks')],
    ),
  ],
)
class WorkbenchShellRoute extends StatefulShellRouteData {
  const WorkbenchShellRoute();

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => WorkspaceShell(navigationShell: navigationShell);
}

class TextBranch extends StatefulShellBranchData {
  const TextBranch();
}

class MediaBranch extends StatefulShellBranchData {
  const MediaBranch();
}

class TasksBranch extends StatefulShellBranchData {
  const TasksBranch();
}

class TextRoute extends GoRouteData with $TextRoute {
  const TextRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const TextPage();
}

class MediaRoute extends GoRouteData with $MediaRoute {
  const MediaRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const MediaPage();
}

class TasksRoute extends GoRouteData with $TasksRoute {
  const TasksRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) => const TasksPage();
}

@TypedGoRoute<CapabilityRoute>(path: '/capabilities/:id')
class CapabilityRoute extends GoRouteData with $CapabilityRoute {
  const CapabilityRoute({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      CapabilityPage(id: id);
}
