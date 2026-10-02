import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workbench_app/features/workspace/domain/id_selection.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

part 'document_selection_providers.g.dart';

@riverpod
class DocumentSelection extends _$DocumentSelection {
  @override
  IdSelection build() {
    ref.listen(workspaceStateProvider, (_, next) {
      final snapshot = next.value?.snapshot;
      if (snapshot != null) {
        state = state.retain(snapshot.documents.map((item) => item.id));
      }
    });
    return IdSelection();
  }

  void toggle(
    String id,
    List<String> visible, {
    bool range = false,
    bool additive = false,
  }) => state = state.toggle(id, visible, range: range, additive: additive);
  void selectAll(Iterable<String> visible) => state = state.selectAll(visible);
  void clear() => state = IdSelection();
  void deleteSelected() {
    ref.read(workspaceSessionProvider).deleteDocuments(state.ids);
    clear();
  }

  void reorder(List<String> ids) =>
      ref.read(workspaceSessionProvider).reorderDocuments(ids);
}
