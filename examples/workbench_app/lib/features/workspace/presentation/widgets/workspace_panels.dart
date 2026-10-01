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
        title: '文本资料',
        search: KoiSearchField(
          key: const ValueKey('document-search'),
          initialValue: query,
          hintText: '搜索资料',
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
                        message: '未保存',
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          semanticLabel: '未保存',
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
            if (documents.isEmpty) const Text('没有匹配的资料'),
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
        title: '媒体分类',
        search: KoiSearchField(
          key: const ValueKey('media-search'),
          initialValue: query,
          hintText: '搜索素材',
          onChanged: ref.read(mediaSearchProvider.notifier).setQuery,
        ),
        child: ListView(
          key: const PageStorageKey('sidebar-media-scroll'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            KoiSelectableListTile(
              title: const Text('全部'),
              trailing: Text('${assets.length}'),
              selected: kind == null,
              onTap: () => ref.read(mediaFilterProvider.notifier).setKind(null),
            ),
            KoiSelectableListTile(
              title: const Text('图片'),
              trailing: Text(
                '${assets.where((asset) => asset.kind == MediaKind.image).length}',
              ),
              selected: kind == MediaKind.image,
              onTap: () => ref
                  .read(mediaFilterProvider.notifier)
                  .setKind(MediaKind.image),
            ),
            KoiSelectableListTile(
              title: const Text('视频'),
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
              '导入的素材副本保存在当前工作区；切换视图会暂停视频并保留播放位置。',
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
      title: '任务概览',
      child: ListView(
        key: const PageStorageKey('sidebar-tasks-scroll'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          Text('${counts.todos} 项待办未完成'),
          const SizedBox(height: 8),
          Text('${counts.jobs} 项 IO 作业处理中'),
          const SizedBox(height: 24),
          Text(
            '任务在切换视图时继续运行。取消会停止读取并清理暂存内容。',
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
        title: '资料详情',
        child: ListView(
          key: const PageStorageKey('detail-text-scroll'),
          padding: EdgeInsets.zero,
          children: [
            if (document == null)
              const Text('尚未选择资料')
            else ...[
              KoiPropertyRow(label: '名称', value: Text(document.title)),
              KoiPropertyRow(
                label: '字数',
                value: Text('${document.text.length} 字'),
              ),
              KoiPropertyRow(
                label: '版本',
                value: Text('版本 ${document.revision}'),
              ),
              KoiPropertyRow(
                label: '保存状态',
                value: WorkspaceSaveStatus(document: document),
              ),
              Text(
                '停止输入 500 毫秒后自动保存',
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
        title: '素材详情',
        child: ListView(
          key: const PageStorageKey('detail-media-scroll'),
          padding: EdgeInsets.zero,
          children: [
            if (asset == null)
              const Text('尚未选择素材')
            else ...[
              KoiPropertyRow(label: '名称', value: Text(asset.name)),
              KoiPropertyRow(
                label: '大小',
                value: Text('${asset.byteLength} 字节'),
              ),
              KoiPropertyRow(
                label: '类型',
                value: Text(asset.kind == MediaKind.image ? '图片' : '视频'),
              ),
              KoiPropertyRow(
                label: '缩略图状态',
                value: Text(switch (asset.thumbnailStatus) {
                  ThumbnailStatus.none => '缩略图待生成',
                  ThumbnailStatus.generating => '正在生成缩略图',
                  ThumbnailStatus.ready => '缩略图已保存',
                  ThumbnailStatus.failed => '缩略图失败',
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
                  child: const Text('重试缩略图'),
                ),
            ],
          ],
        ),
      );
    }
    return const _Information(
      title: '任务说明',
      lines: [
        '待办可以新建、重命名、完成和删除。',
        'IO 进度来自实际字节读取。缩略图处理采用不确定进度。',
        '关闭工作区会取消作业并保存当前草稿。',
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
