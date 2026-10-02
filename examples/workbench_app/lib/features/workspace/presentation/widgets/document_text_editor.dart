import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:workbench_app/l10n/app_strings.dart';

/// Keeps the owning controller authoritative for the complete document while
/// limiting the text paragraph laid out by EditableText for large documents.
/// Segment boundaries expand to grapheme boundaries; no text is discarded.
class DocumentTextEditor extends StatefulWidget {
  const DocumentTextEditor({
    required this.documentId,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.onChanged,
    super.key,
  });
  final String documentId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final ValueChanged<String> onChanged;
  static const segmentLength = 4096;
  static const largeDocumentLength = segmentLength * 2;

  @override
  State<DocumentTextEditor> createState() => _DocumentTextEditorState();
}

class _DocumentTextEditorState extends State<DocumentTextEditor> {
  final _segment = TextEditingController();
  final _previousStarts = <int>[];
  late String _sourceText;
  var _segmented = false;
  var _start = 0;
  var _end = 0;
  var _generation = 0;
  var _updatingFull = false;
  var _updatingSegment = false;
  var _resegmentScheduled = false;

  @override
  void initState() {
    super.initState();
    _segment.addListener(_segmentChanged);
    _attach();
  }

  void _attach() {
    _sourceText = widget.controller.text;
    _segmented = _sourceText.length > DocumentTextEditor.largeDocumentLength;
    if (_segmented) _locate(widget.controller.selection.extentOffset);
    widget.controller.addListener(_fullChanged);
  }

  @override
  void didUpdateWidget(DocumentTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_fullChanged);
      _attach();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fullChanged);
    _segment.dispose();
    super.dispose();
  }

  int _segmentEnd(int start) {
    final target = math.min(
      start + DocumentTextEditor.segmentLength,
      _sourceText.length,
    );
    // CharacterRange.at uses UTF-16 offsets and expands only to complete
    // graphemes. Emoji ZWJ sequences, combining marks and CRLF stay intact.
    final range = CharacterRange.at(_sourceText, start, target);
    return _sourceText.length - range.stringAfterLength;
  }

  void _locate(int offset) {
    _previousStarts.clear();
    _start = 0;
    _end = _segmentEnd(_start);
    final position = offset.clamp(0, _sourceText.length);
    while (_end < position && _end < _sourceText.length) {
      _previousStarts.add(_start);
      _start = _end;
      _end = _segmentEnd(_start);
    }
    _generation++;
    _loadSegment();
  }

  void _loadSegment() {
    final full = widget.controller.value;
    final length = _end - _start;
    final selection = full.selection.isValid
        ? TextSelection(
            baseOffset: (full.selection.baseOffset - _start).clamp(0, length),
            extentOffset: (full.selection.extentOffset - _start).clamp(
              0,
              length,
            ),
            affinity: full.selection.affinity,
            isDirectional: full.selection.isDirectional,
          )
        : const TextSelection.collapsed(offset: 0);
    final composing =
        full.composing.isValid &&
            full.composing.start >= _start &&
            full.composing.end <= _end
        ? TextRange(
            start: full.composing.start - _start,
            end: full.composing.end - _start,
          )
        : TextRange.empty;
    _updatingSegment = true;
    try {
      _segment.value = TextEditingValue(
        text: _sourceText.substring(_start, _end),
        selection: selection,
        composing: composing,
      );
    } finally {
      _updatingSegment = false;
    }
  }

  void _fullChanged() {
    if (_updatingFull) return;
    final full = widget.controller.value;
    final changed = _sourceText != full.text;
    _sourceText = full.text;
    if (!_segmented) {
      if (_sourceText.length <= DocumentTextEditor.largeDocumentLength ||
          !full.composing.isCollapsed) {
        return;
      }
      _segmented = true;
      _locate(full.selection.extentOffset);
    } else if (changed ||
        full.selection.extentOffset < _start ||
        full.selection.extentOffset > _end) {
      _locate(full.selection.extentOffset);
    } else {
      _loadSegment();
    }
    setState(() {});
  }

  void _segmentChanged() {
    if (_updatingSegment) return;
    final value = _segment.value;
    final next = _sourceText.replaceRange(_start, _end, value.text);
    final changed = next != _sourceText;
    _sourceText = next;
    _end = _start + value.text.length;
    _updatingFull = true;
    try {
      widget.controller.value = TextEditingValue(
        text: next,
        selection: value.selection.isValid
            ? TextSelection(
                baseOffset: _start + value.selection.baseOffset,
                extentOffset: _start + value.selection.extentOffset,
                affinity: value.selection.affinity,
                isDirectional: value.selection.isDirectional,
              )
            : const TextSelection.collapsed(offset: -1),
        composing: value.composing.isValid
            ? TextRange(
                start: _start + value.composing.start,
                end: _start + value.composing.end,
              )
            : TextRange.empty,
      );
    } finally {
      _updatingFull = false;
    }
    if (changed) widget.onChanged(next);
    setState(() {});
    // Keep a large paste in the full controller immediately, then reduce the
    // displayed segment before the next frame. Never rewrite an active IME span.
    if (!_resegmentScheduled &&
        value.composing.isCollapsed &&
        value.text.length > DocumentTextEditor.largeDocumentLength) {
      _resegmentScheduled = true;
      scheduleMicrotask(() {
        _resegmentScheduled = false;
        if (!mounted || !_segment.value.composing.isCollapsed) return;
        _locate(widget.controller.selection.extentOffset);
        setState(() {});
      });
    }
  }

  void _move(bool forward) {
    if (!_segment.value.composing.isCollapsed) return;
    if (forward) {
      if (_end == _sourceText.length) return;
      _previousStarts.add(_start);
      _start = _end;
      _end = _segmentEnd(_start);
    } else {
      if (_previousStarts.isEmpty) return;
      _end = _start;
      _start = _previousStarts.removeLast();
    }
    _updatingFull = true;
    try {
      widget.controller.value = widget.controller.value.copyWith(
        selection: TextSelection.collapsed(offset: _start),
        composing: TextRange.empty,
      );
    } finally {
      _updatingFull = false;
    }
    _generation++;
    _loadSegment();
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() {});
  }

  Widget _field() => TextField(
    key: ValueKey('editor-${widget.documentId}'),
    controller: _segmented ? _segment : widget.controller,
    focusNode: widget.focusNode,
    scrollController: widget.scrollController,
    expands: true,
    maxLines: null,
    minLines: null,
    style: Theme.of(context).textTheme.bodyLarge,
    textAlignVertical: TextAlignVertical.top,
    decoration: InputDecoration(
      hintText: context.l10n.writeContent,
      filled: false,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    onChanged: _segmented ? null : widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    if (!_segmented) return _field();
    final composing = !_segment.value.composing.isCollapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              key: const ValueKey('document-segment-previous'),
              onPressed: composing || _previousStarts.isEmpty
                  ? null
                  : () => _move(false),
              child: Text(context.l10n.documentSegmentPrevious),
            ),
            OutlinedButton(
              key: const ValueKey('document-segment-next'),
              onPressed: composing || _end == _sourceText.length
                  ? null
                  : () => _move(true),
              child: Text(context.l10n.documentSegmentNext),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            composing
                ? context.l10n.documentSegmentComposing
                : context.l10n.documentSegmentPosition(
                    _previousStarts.length + 1,
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          // A segment switch starts a separate editing/undo scope, so an undo
          // from an earlier segment cannot replace the current segment's text.
          child: KeyedSubtree(key: ValueKey(_generation), child: _field()),
        ),
      ],
    );
  }
}
