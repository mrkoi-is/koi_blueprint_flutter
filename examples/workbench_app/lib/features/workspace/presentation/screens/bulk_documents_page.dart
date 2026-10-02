import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workbench_app/features/workspace/presentation/providers/document_selection_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/l10n/app_strings.dart';

Widget buildBulkDocumentsPage(BuildContext context) =>
    const BulkDocumentsPage();

class BulkDocumentsPage extends ConsumerStatefulWidget {
  const BulkDocumentsPage({super.key});
  @override
  ConsumerState<BulkDocumentsPage> createState() => _BulkDocumentsPageState();
}

class _BulkDocumentsPageState extends ConsumerState<BulkDocumentsPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final selection = ref.watch(documentSelectionProvider);
    final controller = ref.read(documentSelectionProvider.notifier);
    final documents = ref.watch(visibleDocumentsProvider(_query));
    return Scaffold(
      appBar: AppBar(title: Text(strings.bulkDocumentsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(labelText: strings.bulkFilter),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(strings.bulkSelected(selection.ids.length)),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: selection.ids.isEmpty ? null : controller.clear,
                child: Text(strings.bulkClear),
              ),
              TextButton(
                onPressed: selection.ids.isEmpty
                    ? null
                    : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              strings.bulkDeleteConfirm(selection.ids.length),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(strings.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(strings.bulkDelete),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          controller.deleteSelected();
                        }
                      },
                child: Text(strings.bulkDelete),
              ),
            ],
          ),
          Expanded(
            child: documents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (items) {
                final ids = items.map((item) => item.id).toList();
                void move(int from, int to) {
                  if (_query.isNotEmpty || to < 0 || to >= ids.length) {
                    return;
                  }
                  final reordered = List.of(ids);
                  reordered.insert(to, reordered.removeAt(from));
                  controller.reorder(reordered);
                }

                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyA,
                      control: true,
                    ): () =>
                        controller.selectAll(ids),
                    const SingleActivator(
                      LogicalKeyboardKey.keyA,
                      meta: true,
                    ): () =>
                        controller.selectAll(ids),
                  },
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: items.length,
                    onReorderItem: move,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return CallbackShortcuts(
                        key: ValueKey(item.id),
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.arrowUp,
                            alt: true,
                          ): () =>
                              move(index, index - 1),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowDown,
                            alt: true,
                          ): () =>
                              move(index, index + 1),
                        },
                        child: CheckboxListTile(
                          value: selection.ids.contains(item.id),
                          onChanged: (_) => controller.toggle(
                            item.id,
                            ids,
                            range: HardwareKeyboard.instance.isShiftPressed,
                            additive:
                                HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed,
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            item.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: _query.isEmpty
                              ? ReorderableDragStartListener(
                                  index: index,
                                  child: Semantics(
                                    label: strings.bulkReorder,
                                    child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
