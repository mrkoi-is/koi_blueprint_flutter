import 'package:flutter/material.dart';
import 'package:koi_admin_app/core/router/app_navigation.dart';

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
  Widget build(BuildContext context) {
    final wideLayout = MediaQuery.sizeOf(context).width >= 960;

    void onDestinationSelected(int index) {
      switch (index) {
        case 1:
          context.goToSettings();
          return;
        default:
          context.goToDashboard();
          return;
      }
    }

    final destinations = const [
      NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: '总览'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
    ];

    if (wideLayout) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: Text('总览'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: Text('设置'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        destinations: destinations,
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }
}
