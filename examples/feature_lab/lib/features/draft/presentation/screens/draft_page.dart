import 'package:feature_lab/features/draft/presentation/providers/draft_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DraftPage extends ConsumerWidget {
  const DraftPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(draftControllerProvider);
    final busy = value.isLoading || (value.value?.isSaving ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Draft')),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (value.hasError || value.value?.operationFailure != null)
            const Text('Draft operation failed'),
          if (value.hasValue)
            _DraftTextField(
              text: value.value!.text,
              onChanged: (text) =>
                  ref.read(draftControllerProvider.notifier).edit(text),
            ),
          FilledButton(
            onPressed: value.hasValue && !busy
                ? () => ref.read(draftControllerProvider.notifier).save()
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Owns the editor's local cursor/composition while accepting repository reloads.
class _DraftTextField extends StatefulWidget {
  const _DraftTextField({required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

  @override
  State<_DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<_DraftTextField> {
  late final TextEditingController _controller;
  String? _pendingExternalText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text)
      ..addListener(_applyPendingText);
  }

  @override
  void didUpdateWidget(_DraftTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text == widget.text) {
      _pendingExternalText = null;
    } else if (!_controller.value.composing.isCollapsed) {
      _pendingExternalText = widget.text;
    } else {
      _replaceText(widget.text);
    }
  }

  void _applyPendingText() {
    final pending = _pendingExternalText;
    if (pending == null || !_controller.value.composing.isCollapsed) return;
    _pendingExternalText = null;
    if (_controller.text != pending) _replaceText(pending);
  }

  void _replaceText(String text) {
    final current = _controller.selection;
    final offset = current.isValid
        ? current.extentOffset.clamp(0, text.length)
        : text.length;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_applyPendingText);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextFormField(controller: _controller, onChanged: widget.onChanged);
}
