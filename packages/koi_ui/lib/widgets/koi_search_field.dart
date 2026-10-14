import 'package:koi_ui/l10n/koi_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';

/// Theme-sized search input with clearing and optional host-owned controller.
class KoiSearchField extends StatefulWidget {
  const KoiSearchField({
    required this.hintText,
    this.initialValue,
    this.controller,
    this.onChanged,
    super.key,
  }) : assert(controller == null || initialValue == null);
  final String hintText;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<KoiSearchField> createState() => _KoiSearchFieldState();
}

class _KoiSearchFieldState extends State<KoiSearchField> {
  late TextEditingController _controller;
  final _focus = FocusNode();
  void _attach() {
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(KoiSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_changed);
      if (oldWidget.controller == null) _controller.dispose();
      _attach();
    } else if (widget.controller == null &&
        oldWidget.initialValue != widget.initialValue &&
        _controller.text != (widget.initialValue ?? '')) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    focusNode: _focus,
    onChanged: widget.onChanged,
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      hintText: widget.hintText,
      prefixIcon: const Icon(Icons.search, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 36),
      suffixIconConstraints: BoxConstraints(
        minWidth: KoiThemeTokens.of(context).controlHeight,
        minHeight: KoiThemeTokens.of(context).controlHeight,
      ),
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: KoiUiStrings.of(context).clearSearch,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
                _focus.requestFocus();
              },
            ),
    ),
  );
}
