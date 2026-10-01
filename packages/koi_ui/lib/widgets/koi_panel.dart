import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

/// Content-panel recipe: fixed heading/search and independently scrolling body.
/// The host supplies scrolling widgets and owns their restoration identity.
class KoiPanel extends StatelessWidget {
  const KoiPanel({
    required this.title,
    required this.child,
    this.search,
    super.key,
  });
  final String title;
  final Widget child;
  final Widget? search;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .6),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KoiSpace.control,
                KoiSpace.section,
                KoiSpace.control,
                KoiSpace.control,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (search != null) ...[
                    const SizedBox(height: KoiSpace.control),
                    search!,
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoiSpace.control),
            child: child,
          ),
        ),
      ],
    ),
  );
}
