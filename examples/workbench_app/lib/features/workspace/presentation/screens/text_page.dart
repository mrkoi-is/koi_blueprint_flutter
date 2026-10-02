import 'package:workbench_app/l10n/app_strings.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_save_status.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/models/text_view_state.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/document_text_editor.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

class TextPage extends ConsumerStatefulWidget {
  const TextPage({super.key});
  @override
  ConsumerState<TextPage> createState() => _TextPageState();
}

class _TextPageState extends ConsumerState<TextPage> {
  final _editors = <String, TextEditingController>{};
  final _scrolls = <String, ScrollController>{};
  final _focus = <String, FocusNode>{};
  @override
  void dispose() {
    for (final controller in _editors.values) {
      controller.dispose();
    }
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _rename(WorkspaceDocument document) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _DocumentTitleDialog(title: document.title),
    );
    if (mounted && title != null && title.trim().isNotEmpty) {
      ref
          .read(workspaceSessionProvider)
          .renameDocument(document.id, title.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workspaceSessionProvider);
    final state = ref.watch(
      workspaceStateProvider.select(
        (value) => TextViewState(
          documents:
              value.value?.snapshot.documents ??
              session.state.snapshot.documents,
          selectedId:
              value.value?.snapshot.preferences.selectedDocumentId ??
              session.state.snapshot.preferences.selectedDocumentId,
          sidebarWidth: 0,
        ),
      ),
    );
    final selected =
        state.documents
            .where((document) => document.id == state.selectedId)
            .firstOrNull ??
        state.documents.firstOrNull;
    final editor = selected == null
        ? null
        : _editors.putIfAbsent(
            selected.id,
            () => TextEditingController(text: selected.text),
          );
    ref.listen(
      workspaceStateProvider.select((value) => value.value?.snapshot.documents),
      (_, next) {
        for (final document in next ?? <WorkspaceDocument>[]) {
          final controller = _editors[document.id];
          if (controller == null ||
              controller.text == document.text ||
              !controller.value.composing.isCollapsed) {
            continue;
          }
          final selection = controller.selection;
          controller.value = TextEditingValue(
            text: document.text,
            selection: TextSelection.collapsed(
              offset: selection.isValid
                  ? selection.extentOffset.clamp(0, document.text.length)
                  : document.text.length,
            ),
          );
        }
      },
    );
    final theme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style, double fallback) =>
        scaler.scale(style?.fontSize ?? fallback) * (style?.height ?? 1.4);
    final minimumHeight =
        160 +
        lineHeight(theme.titleLarge, 22) * 2 +
        lineHeight(theme.bodyLarge, 16) * 3 +
        lineHeight(theme.bodySmall, 12);
    return KoiReadingPane(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: SizedBox(
            height: math.max(constraints.maxHeight, minimumHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KoiToolbar(
                  padding: const EdgeInsets.only(bottom: 16),
                  actions: [
                    TextButton.icon(
                      key: const ValueKey('new-document'),
                      onPressed: session.createDocument,
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.newDocument),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(session.importFiles(ImportKind.text)),
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(context.l10n.importText),
                    ),
                  ],
                ),
                Expanded(
                  child: selected == null
                      ? KoiEmptyState(
                          title: context.l10n.noDocuments,
                          description: context.l10n.documentsHint,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selected.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.l10n.renameCurrentDocument,
                                  onPressed: () => unawaited(_rename(selected)),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: DocumentTextEditor(
                                key: ValueKey('document-body-${selected.id}'),
                                documentId: selected.id,
                                controller: editor!,
                                focusNode: _focus.putIfAbsent(
                                  selected.id,
                                  FocusNode.new,
                                ),
                                scrollController: _scrolls.putIfAbsent(
                                  selected.id,
                                  ScrollController.new,
                                ),
                                onChanged: (text) =>
                                    session.editDocument(selected.id, text),
                              ),
                            ),
                            const SizedBox(height: 12),
                            WorkspaceSaveStatus(
                              document: selected,
                              includeCount: true,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentTitleDialog extends StatefulWidget {
  const _DocumentTitleDialog({required this.title});
  final String title;
  @override
  State<_DocumentTitleDialog> createState() => _DocumentTitleDialogState();
}

class _DocumentTitleDialogState extends State<_DocumentTitleDialog> {
  late final _controller = TextEditingController(text: widget.title);
  String? _error;

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.documentNameRequired);
      return;
    }
    Navigator.pop(context, title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.renameDocument),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: context.l10n.documentName,
        errorText: _error,
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(context.l10n.confirm)),
    ],
  );
}
