import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:koi_admin_app/core/router/app_navigation.dart';

/// Admin has one primary destination; settings is a pinned utility command.
class HomeShellScaffold extends StatelessWidget {
  const HomeShellScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.child,
  });
  final int currentIndex;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => KoiWorkbenchFrame(
      destinations: const [
        KoiNavigationDestination(
          id: 'dashboard',
          label: '总览',
          icon: Icons.dashboard_outlined,
        ),
      ],
      selectedId: currentIndex == 0 ? 'dashboard' : 'settings',
      onDestinationSelected: (_) => context.goToDashboard(),
      title: Text(title),
      actions: [
        if (currentIndex == 1 && constraints.maxWidth < 600)
          IconButton(
            tooltip: '返回总览',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: context.goToDashboard,
          ),
      ],
      navigationTrailing: IconButton(
        tooltip: '设置',
        isSelected: currentIndex == 1,
        icon: const Icon(Icons.settings_outlined),
        onPressed: context.goToSettings,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: child,
        ),
      ),
    ),
  );
}
