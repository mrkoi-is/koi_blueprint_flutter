import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

/// Revision cleanliness and workspace commit activity are separate facts.
class WorkspaceSaveStatus extends ConsumerWidget {
  const WorkspaceSaveStatus({
    required this.document,
    this.includeCount = false,
    super.key,
  });
  final WorkspaceDocument document;
  final bool includeCount;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(workspaceSessionProvider);
    final activity = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          saving: value.value?.saving ?? session.state.saving,
          error: value.value?.error ?? session.state.error,
        ),
      ),
    );
    final revision = document.dirty ? '未保存' : '已保存';
    final activityLabel = activity.saving
        ? ' · 工作区保存中'
        : activity.error?.startsWith('保存失败：') == true
        ? ' · 工作区保存失败'
        : '';
    return Text(
      '${includeCount ? '${document.text.length} 字 · ' : ''}$revision$activityLabel',
      style: includeCount ? Theme.of(context).textTheme.bodySmall : null,
    );
  }
}
