import 'package:flutter/material.dart';

/// Theme-sized search input. Hosts retain the query and its business behavior.
class KoiSearchField extends StatelessWidget {
  const KoiSearchField({
    required this.hintText,
    this.initialValue,
    this.onChanged,
    super.key,
  });

  final String hintText;
  final String? initialValue;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    onChanged: onChanged,
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      hintText: hintText,
      prefixIcon: const Icon(Icons.search, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 36),
    ),
  );
}
