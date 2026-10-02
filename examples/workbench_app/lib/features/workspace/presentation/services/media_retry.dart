import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workbench_app/core/router/app_navigation.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

/// Mount the selected video before asking its player for a rendered first frame.
Future<void> retryVideoThumbnail(
  BuildContext context,
  WidgetRef ref,
  WorkspaceAsset asset,
) async {
  final session = ref.read(workspaceSessionProvider);
  final preview = ref.read(mediaPreviewSessionProvider);
  final previousAttempts = {
    for (final job in session.state.snapshot.jobs) job.id: job.currentAttempt,
  };
  session.updatePreferences(
    session.state.snapshot.preferences.copyWith(selectedAssetId: asset.id),
  );
  context.goToMedia();
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) {
    return;
  }
  await preview.select(asset);
  // MediaPage may have started the same retry as the newly selected page mounted.
  final attempted = session.state.snapshot.jobs.any(
    (job) =>
        job.assetId == asset.id &&
        job.kind == JobKind.thumbnail &&
        previousAttempts[job.id] != job.currentAttempt,
  );
  if (!attempted) {
    await preview.retryThumbnail(asset);
  }
}
