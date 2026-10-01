import 'package:flutter/material.dart';

/// A wrapping property value with a quiet, theme-driven label.
class KoiPropertyRow extends StatelessWidget {
  const KoiPropertyRow({required this.label, required this.value, super.key});
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium,
          child: value,
        ),
      ],
    ),
  );
}
