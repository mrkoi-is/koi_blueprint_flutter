import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

class KoiSection extends StatelessWidget {
  const KoiSection({
    required this.title,
    required this.child,
    this.description,
    this.actions = const [],
    super.key,
  });

  final Widget title;
  final Widget child;
  final Widget? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: KoiSpace.md,
        runSpacing: KoiSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.titleMedium,
            child: title,
          ),
          ...actions,
        ],
      ),
      if (description != null) ...[
        const SizedBox(height: KoiSpace.xs),
        DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodySmall,
          child: description!,
        ),
      ],
      const SizedBox(height: KoiSpace.md),
      child,
    ],
  );
}
