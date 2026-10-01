import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_preview_session.dart';

class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({super.key});
  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  bool _grid = true;
  String? _requestedAsset;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updatePreview(ref.read(workspaceSessionProvider).state);
      }
    });
  }

  void _updatePreview(WorkspaceState state) {
    final selected = state.snapshot.assets
        .where(
          (asset) => asset.id == state.snapshot.preferences.selectedAssetId,
        )
        .firstOrNull;
    if (_requestedAsset == selected?.id) {
      return;
    }
    _requestedAsset = selected?.id;
    unawaited(ref.read(mediaPreviewSessionProvider).select(selected));
  }

  void _select(WorkspaceAsset asset) {
    final session = ref.read(workspaceSessionProvider);
    session.updatePreferences(
      session.state.snapshot.preferences.copyWith(selectedAssetId: asset.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workspaceSessionProvider);
    final state = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          assets: value.value?.snapshot.assets ?? session.state.snapshot.assets,
          selectedAssetId:
              value.value?.snapshot.preferences.selectedAssetId ??
              session.state.snapshot.preferences.selectedAssetId,
        ),
      ),
    );
    ref.listen(
      workspaceStateProvider.select(
        (value) => value.value?.snapshot.preferences.selectedAssetId,
      ),
      (_, _) => _updatePreview(session.state),
    );
    final filter = ref.watch(mediaFilterProvider);
    final query = ref.watch(mediaSearchProvider);
    final assets = state.assets
        .where(
          (asset) =>
              (filter == null || asset.kind == filter) &&
              asset.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final selected = state.assets
        .where((asset) => asset.id == state.selectedAssetId)
        .firstOrNull;
    final preview = ref.watch(mediaPreviewSessionProvider);
    return Column(
      children: [
        KoiToolbar(
          actions: [
            TextButton.icon(
              onPressed: () => unawaited(session.importFiles(ImportKind.media)),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('导入图片 / 视频'),
            ),
            IconButton(
              tooltip: _grid ? '切换列表' : '切换网格',
              onPressed: () => setState(() => _grid = !_grid),
              icon: Icon(
                _grid ? Icons.view_list_outlined : Icons.grid_view_outlined,
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final textStyle = Theme.of(context).textTheme.bodyMedium;
              final scaler = MediaQuery.textScalerOf(context);
              final tileHeight = math.max(
                180.0,
                80 +
                    scaler.scale(textStyle?.fontSize ?? 14) *
                        (textStyle?.height ?? 1.4) *
                        2 +
                    math.max(48, scaler.scale(18) + 24),
              );
              final library = assets.isEmpty
                  ? const SingleChildScrollView(
                      child: KoiEmptyState(
                        title: '暂无匹配素材',
                        description: '导入 PNG/JPEG 图片或 MP4 视频',
                      ),
                    )
                  : _grid
                  ? GridView.builder(
                      key: const PageStorageKey('media-grid'),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisExtent: tileHeight,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: assets.length,
                      itemBuilder: (context, index) => _AssetTile(
                        asset: assets[index],
                        selected: selected?.id == assets[index].id,
                        onTap: () => _select(assets[index]),
                      ),
                    )
                  : ListView.builder(
                      key: const PageStorageKey('media-list'),
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        return KoiSelectableListTile(
                          title: Text(asset.name),
                          subtitle: Text(
                            '${asset.kind == MediaKind.image ? '图片' : '视频'} · ${asset.byteLength} 字节',
                          ),
                          selected: selected?.id == asset.id,
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: asset.thumbnailKey == null
                                ? Icon(
                                    asset.kind == MediaKind.image
                                        ? Icons.image_outlined
                                        : Icons.movie_outlined,
                                  )
                                : _StoredImage(storageKey: asset.thumbnailKey!),
                          ),
                          onTap: () => _select(asset),
                        );
                      },
                    );
              final viewer = _MediaViewer(asset: selected, preview: preview);
              // Both regions retain their position in this Flex when its axis changes.
              return Flex(
                direction: wide ? Axis.horizontal : Axis.vertical,
                children: [
                  Expanded(flex: wide ? 2 : 1, child: library),
                  Expanded(flex: wide ? 3 : 1, child: viewer),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssetTile extends ConsumerWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });
  final WorkspaceAsset asset;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailKey = asset.thumbnailKey;
    final readFailed =
        thumbnailKey != null &&
        ref.watch(assetBytesProvider(thumbnailKey)).hasError;
    final status = readFailed
        ? '缩略图读取失败'
        : switch (asset.thumbnailStatus) {
            ThumbnailStatus.none =>
              asset.kind == MediaKind.video ? '打开预览生成缩略图' : '缩略图待生成',
            ThumbnailStatus.generating => '正在生成缩略图',
            ThumbnailStatus.ready => null,
            ThumbnailStatus.failed => '缩略图失败',
          };
    return Card(
      color: selected ? KoiThemeTokens.of(context).selectedBackground : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                button: true,
                selected: selected,
                label:
                    '${asset.kind == MediaKind.image ? '图片' : '视频'}，${asset.name}',
                value: status,
                child: Tooltip(
                  message: asset.name,
                  excludeFromSemantics: true,
                  child: InkWell(
                    onTap: onTap,
                    child: ExcludeSemantics(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                Expanded(
                                  child: asset.thumbnailKey == null
                                      ? Icon(
                                          asset.kind == MediaKind.image
                                              ? Icons.image_outlined
                                              : Icons.movie_outlined,
                                          size: 40,
                                        )
                                      : _StoredImage(
                                          storageKey: asset.thumbnailKey!,
                                          fit: BoxFit.contain,
                                          showReadErrorAction: false,
                                        ),
                                ),
                                Text(
                                  asset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (status != null)
                                  Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (selected)
                            PositionedDirectional(
                              top: 8,
                              end: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (readFailed)
            TextButton(
              onPressed: () => ref.invalidate(assetBytesProvider(thumbnailKey)),
              child: Semantics(
                label: '重试读取缩略图：${asset.name}',
                excludeSemantics: true,
                child: const Text('重试读取'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoredImage extends ConsumerWidget {
  const _StoredImage({
    required this.storageKey,
    this.fit = BoxFit.contain,
    this.showReadErrorAction = true,
  });
  final String storageKey;
  final BoxFit fit;
  final bool showReadErrorAction;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(assetBytesProvider(storageKey))
      .when(
        data: (bytes) => LayoutBuilder(
          builder: (context, constraints) {
            final ratio = MediaQuery.devicePixelRatioOf(context);
            return Image(
              image: ResizeImage(
                MemoryImage(bytes),
                width: constraints.maxWidth.isFinite
                    ? math.max(1, (constraints.maxWidth * ratio).ceil())
                    : null,
                height: constraints.maxHeight.isFinite
                    ? math.max(1, (constraints.maxHeight * ratio).ceil())
                    : null,
                policy: ResizeImagePolicy.fit,
              ),
              fit: fit,
              errorBuilder: (_, error, _) => Text('图片解码失败：$error'),
            );
          },
        ),
        error: (error, _) => !showReadErrorAction
            ? const Icon(Icons.broken_image_outlined, size: 40)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('图片读取失败：$error'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(assetBytesProvider(storageKey)),
                    child: const Text('重试读取'),
                  ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
      );
}

class _MediaViewer extends StatelessWidget {
  const _MediaViewer({required this.asset, required this.preview});
  final WorkspaceAsset? asset;
  final MediaPreviewSession preview;
  @override
  Widget build(BuildContext context) {
    final selected = asset;
    if (selected == null) {
      return const SingleChildScrollView(
        child: KoiEmptyState(
          title: '选择素材',
          description: '图片支持缩放；视频支持播放、暂停和拖动进度',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                selected.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (selected.kind == MediaKind.image)
                SizedBox(
                  height: math.max(160, constraints.maxHeight - 84),
                  child: InteractiveViewer(
                    key: ValueKey('image-viewer-${selected.id}'),
                    minScale: 0.25,
                    maxScale: 8,
                    child: Center(
                      child: _StoredImage(storageKey: selected.storageKey),
                    ),
                  ),
                )
              else
                ListenableBuilder(
                  listenable: preview,
                  builder: (context, _) {
                    final player = preview.playback;
                    return Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (player != null) player.surface,
                              if (preview.loading)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              if (player == null && !preview.loading)
                                const Center(
                                  child: Icon(Icons.movie_outlined, size: 48),
                                ),
                            ],
                          ),
                        ),
                        if (preview.error != null)
                          Text(
                            preview.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: player?.playing == true
                                  ? '暂停视频'
                                  : '播放视频',
                              onPressed: player == null
                                  ? null
                                  : () => unawaited(preview.togglePlaying()),
                              icon: Icon(
                                player?.playing == true
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            Expanded(
                              child: MergeSemantics(
                                child: Semantics(
                                  label: '播放进度',
                                  child: Slider(
                                    semanticFormatterCallback: (value) =>
                                        '已播放 ${_playbackTime(Duration(milliseconds: value.round()))}，'
                                        '共 ${_playbackTime(player?.duration ?? Duration.zero)}',
                                    value:
                                        player == null ||
                                            player.duration.inMilliseconds <= 0
                                        ? 0
                                        : player.position.inMilliseconds
                                              .clamp(
                                                0,
                                                player.duration.inMilliseconds,
                                              )
                                              .toDouble(),
                                    max:
                                        player == null ||
                                            player.duration.inMilliseconds <= 0
                                        ? 1
                                        : player.duration.inMilliseconds
                                              .toDouble(),
                                    onChanged:
                                        player == null ||
                                            player.duration.inMilliseconds <= 0
                                        ? null
                                        : (value) => unawaited(
                                            preview.seek(
                                              Duration(
                                                milliseconds: value.round(),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _playbackTime(player?.position ?? Duration.zero),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.volume_up_outlined),
                            Expanded(
                              child: MergeSemantics(
                                child: Semantics(
                                  label: '音量',
                                  child: Slider(
                                    semanticFormatterCallback: (value) =>
                                        '${value.round()}%',
                                    value: player?.volume.clamp(0, 100) ?? 100,
                                    max: 100,
                                    onChanged: player == null
                                        ? null
                                        : (value) => unawaited(
                                            preview.setVolume(value),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (preview.error != null)
                          TextButton(
                            onPressed: () =>
                                unawaited(preview.retryThumbnail(selected)),
                            child: const Text('重试视频预览 / 缩略图'),
                          ),
                      ],
                    );
                  },
                ),
              if (selected.thumbnailStatus == ThumbnailStatus.failed)
                TextButton(
                  onPressed: () => selected.kind == MediaKind.video
                      ? unawaited(preview.retryThumbnail(selected))
                      : unawaited(refRetryThumbnail(context, selected.id)),
                  child: const Text('重试缩略图'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> refRetryThumbnail(BuildContext context, String id) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(workspaceSessionProvider);
  final job = session.state.snapshot.jobs
      .where((job) => job.assetId == id && job.kind == JobKind.thumbnail)
      .lastOrNull;
  if (job != null) {
    await session.retryJob(job.id);
  }
}

String _playbackTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 31);
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
