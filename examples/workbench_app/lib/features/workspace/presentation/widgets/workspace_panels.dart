import 'package:workbench_app/l10n/app_strings.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_save_status.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/models/text_view_state.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_retry.dart';

class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(workspaceSessionProvider);
    if (index == 0) {
      final state = ref.watch(
        workspaceStateProvider.select(
          (value) => TextViewState(
            documents:
                value.value?.snapshot.documents ??
                session.state.snapshot.documents,
            selectedId: value.value?.snapshot.preferences.selectedDocumentId,
            sidebarWidth: 0,
          ),
        ),
      );
      final query = ref.watch(documentSearchProvider);
      final documents = searchDocuments(state.documents, query);
      return KoiPanel(
        title: context.l10n.text,
        search: KoiSearchField(
          key: const ValueKey('document-search'),
          initialValue: query,
          hintText: context.l10n.searchDocuments,
          onChanged: ref.read(documentSearchProvider.notifier).setQuery,
        ),
        child: ListView(
          key: const PageStorageKey('sidebar-text-scroll'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final document in documents)
              KoiSelectableListTile(
                title: Tooltip(
                  message: document.title,
                  excludeFromSemantics: true,
                  child: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                leading: const Icon(Icons.description_outlined),
                trailing: document.dirty
                    ? Tooltip(
                        message: context.l10n.unsaved,
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          semanticLabel: context.l10n.unsaved,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : null,
                selected: document.id == state.selectedId,
                onTap: () {
                  session.updatePreferences(
                    session.state.snapshot.preferences.copyWith(
                      selectedDocumentId: document.id,
                    ),
                  );
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            if (documents.isEmpty) Text(context.l10n.noMatchingDocuments),
          ],
        ),
      );
    }
    if (index == 1) {
      final assets =
          ref.watch(
            workspaceStateProvider.select(
              (value) => value.value?.snapshot.assets,
            ),
          ) ??
          session.state.snapshot.assets;
      final kind = ref.watch(mediaFilterProvider);
      final query = ref.watch(mediaSearchProvider);
      return KoiPanel(
        title: context.l10n.mediaCategories,
        search: KoiSearchField(
          key: const ValueKey('media-search'),
          initialValue: query,
          hintText: context.l10n.searchMedia,
          onChanged: ref.read(mediaSearchProvider.notifier).setQuery,
        ),
        child: ListView(
          key: const PageStorageKey('sidebar-media-scroll'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            KoiSelectableListTile(
              title: Text(context.l10n.all),
              trailing: Text('${assets.length}'),
              selected: kind == null,
              onTap: () => ref.read(mediaFilterProvider.notifier).setKind(null),
            ),
            KoiSelectableListTile(
              title: Text(context.l10n.image),
              trailing: Text(
                '${assets.where((asset) => asset.kind == MediaKind.image).length}',
              ),
              selected: kind == MediaKind.image,
              onTap: () => ref
                  .read(mediaFilterProvider.notifier)
                  .setKind(MediaKind.image),
            ),
            KoiSelectableListTile(
              title: Text(context.l10n.video),
              trailing: Text(
                '${assets.where((asset) => asset.kind == MediaKind.video).length}',
              ),
              selected: kind == MediaKind.video,
              onTap: () => ref
                  .read(mediaFilterProvider.notifier)
                  .setKind(MediaKind.video),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.mediaStorageHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    final counts = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          todos:
              value.value?.snapshot.todos
                  .where((todo) => !todo.completed)
                  .length ??
              0,
          jobs:
              value.value?.snapshot.jobs.where((job) => !job.terminal).length ??
              0,
        ),
      ),
    );
    return KoiPanel(
      title: context.l10n.taskSummary,
      child: ListView(
        key: const PageStorageKey('sidebar-tasks-scroll'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          Text(context.l10n.incompleteTodos(counts.todos)),
          const SizedBox(height: 8),
          Text(context.l10n.activeJobs(counts.jobs)),
          const SizedBox(height: 24),
          Text(
            context.l10n.taskRunningHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class WorkspaceDetails extends ConsumerWidget {
  const WorkspaceDetails({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(workspaceSessionProvider);
    if (index == 0) {
      final document = ref.watch(
        workspaceStateProvider.select((value) {
          final snapshot = value.value?.snapshot;
          return snapshot?.documents
              .where(
                (document) =>
                    document.id == snapshot.preferences.selectedDocumentId,
              )
              .firstOrNull;
        }),
      );
      return KoiPanel(
        title: context.l10n.documentDetails,
        child: ListView(
          key: const PageStorageKey('detail-text-scroll'),
          padding: EdgeInsets.zero,
          children: [
            if (document == null)
              Text(context.l10n.noDocumentSelected)
            else ...[
              KoiPropertyRow(
                label: context.l10n.name,
                value: Text(document.title),
              ),
              KoiPropertyRow(
                label: context.l10n.characterCountLabel,
                value: Text(context.l10n.characterCount(document.text.length)),
              ),
              KoiPropertyRow(
                label: context.l10n.revisionLabel,
                value: Text(context.l10n.revision(document.revision)),
              ),
              KoiPropertyRow(
                label: context.l10n.saveStatus,
                value: WorkspaceSaveStatus(document: document),
              ),
              Text(
                context.l10n.autosaveHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }
    if (index == 1) {
      final asset = ref.watch(
        workspaceStateProvider.select((value) {
          final snapshot = value.value?.snapshot;
          return snapshot?.assets
              .where(
                (asset) => asset.id == snapshot.preferences.selectedAssetId,
              )
              .firstOrNull;
        }),
      );
      return KoiPanel(
        title: context.l10n.mediaDetails,
        child: ListView(
          key: const PageStorageKey('detail-media-scroll'),
          padding: EdgeInsets.zero,
          children: [
            if (asset == null)
              Text(context.l10n.noMediaSelected)
            else ...[
              KoiPropertyRow(label: context.l10n.name, value: Text(asset.name)),
              KoiPropertyRow(
                label: context.l10n.size,
                value: Text(context.l10n.byteCount(asset.byteLength)),
              ),
              KoiPropertyRow(
                label: context.l10n.type,
                value: Text(
                  asset.kind == MediaKind.image
                      ? context.l10n.image
                      : context.l10n.video,
                ),
              ),
              KoiPropertyRow(
                label: context.l10n.thumbnailStatus,
                value: Text(switch (asset.thumbnailStatus) {
                  ThumbnailStatus.none => context.l10n.thumbnailPending,
                  ThumbnailStatus.generating =>
                    context.l10n.thumbnailGenerating,
                  ThumbnailStatus.ready => context.l10n.thumbnailSaved,
                  ThumbnailStatus.failed => context.l10n.thumbnailFailed,
                }),
              ),
              if (asset.thumbnailError != null) Text(asset.thumbnailError!),
              if (asset.thumbnailStatus == ThumbnailStatus.failed)
                TextButton(
                  onPressed: () {
                    if (asset.kind == MediaKind.video) {
                      unawaited(retryVideoThumbnail(context, ref, asset));
                    } else {
                      final job = session.state.snapshot.jobs
                          .where(
                            (job) =>
                                job.assetId == asset.id &&
                                job.kind == JobKind.thumbnail,
                          )
                          .lastOrNull;
                      if (job != null) {
                        unawaited(session.retryJob(job.id));
                      }
                    }
                  },
                  child: Text(context.l10n.retryThumbnail),
                ),
            ],
          ],
        ),
      );
    }
    return _Information(
      title: context.l10n.taskHelp,
      lines: [
        context.l10n.todoHelp,
        context.l10n.jobHelp,
        context.l10n.closeHelp,
      ],
    );
  }
}

class _Information extends StatelessWidget {
  const _Information({required this.title, required this.lines});
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => KoiPanel(
    title: title,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              lines[i],
              style: i == lines.length - 1
                  ? Theme.of(context).textTheme.bodySmall
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    ),
  );
}
