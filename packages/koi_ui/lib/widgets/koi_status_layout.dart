import 'package:flutter/material.dart';

/// Centers feedback when it fits and makes every action reachable when it does not.
class KoiStatusLayout extends StatelessWidget {
  const KoiStatusLayout({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
        ),
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
}
