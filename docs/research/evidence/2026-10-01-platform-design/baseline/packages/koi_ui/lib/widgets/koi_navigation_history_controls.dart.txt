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
        tooltip: '后退',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back, size: 20),
      ),
      IconButton(
        tooltip: '前进',
        onPressed: onForward,
        icon: const Icon(Icons.arrow_forward, size: 20),
      ),
    ],
  );
}
