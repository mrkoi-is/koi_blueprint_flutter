import 'package:koi_ui/l10n/koi_ui_strings.dart';
import 'package:flutter/material.dart';

/// The host owns history; null callbacks expose disabled navigation states.
class KoiNavigationHistoryControls extends StatelessWidget {
  const KoiNavigationHistoryControls({super.key, this.onBack, this.onForward});

  final VoidCallback? onBack;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: KoiUiStrings.of(context).back,
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back, size: 20),
      ),
      IconButton(
        tooltip: KoiUiStrings.of(context).forward,
        onPressed: onForward,
        icon: const Icon(Icons.arrow_forward, size: 20),
      ),
    ],
  );
}
