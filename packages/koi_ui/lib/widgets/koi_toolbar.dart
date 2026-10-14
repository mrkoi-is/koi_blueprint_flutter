import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

/// Wrapping action row, with no route, command or session ownership.
class KoiToolbar extends StatelessWidget {
  const KoiToolbar({
    required this.actions,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    super.key,
  });

  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: KoiSpace.sm,
        runSpacing: KoiSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions,
      ),
    ),
  );
}
