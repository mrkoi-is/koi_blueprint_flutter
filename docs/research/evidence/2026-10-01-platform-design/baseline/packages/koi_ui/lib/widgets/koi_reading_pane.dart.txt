import 'package:flutter/material.dart';

/// Bounds document content while retaining the parent's vertical constraints.
class KoiReadingPane extends StatelessWidget {
  const KoiReadingPane({
    required this.child,
    this.maxWidth = 800,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
