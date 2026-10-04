import 'package:workbench_app/l10n/app_strings.dart';
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
    final activity = ref.watch(
      workspaceSnapshotProvider.select(
        (value) => (saving: value.saving, error: value.error),
      ),
    );
    final revision = document.dirty ? context.l10n.unsaved : context.l10n.saved;
    final activityLabel = activity.saving
        ? ' · ${context.l10n.saving}'
        : activity.error?.startsWith('保存失败：') == true
        ? ' · ${context.l10n.saveFailed}'
        : '';
    return Text(
      '${includeCount ? '${context.l10n.characterCount(document.text.length)} · ' : ''}$revision$activityLabel',
      style: includeCount ? Theme.of(context).textTheme.bodySmall : null,
    );
  }
}
