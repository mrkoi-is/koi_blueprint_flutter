import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_preview_session.dart';

part 'workspace_providers.g.dart';

/// Borrowed from bootstrap; this provider never closes the workspace.
@Riverpod(keepAlive: true)
WorkspaceSession workspaceSession(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject a WorkspaceSession');

/// Bootstrap owns the player and awaits its cleanup before closing storage.
@Riverpod(keepAlive: true)
MediaPreviewSession mediaPreviewSession(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject a MediaPreviewSession');

@Riverpod(keepAlive: true)
Stream<WorkspaceState> workspaceState(Ref ref) {
  final session = ref.watch(workspaceSessionProvider);
  final events = StreamController<WorkspaceState>();
  final subscription = session.changes.listen(
    events.add,
    onError: events.addError,
  );
  events.add(session.state);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(events.close());
  });
  return events.stream;
}

@riverpod
AsyncValue<List<WorkspaceDocument>> visibleDocuments(Ref ref, String query) =>
    ref
        .watch(workspaceStateProvider)
        .whenData((state) => searchDocuments(state.snapshot.documents, query));

@riverpod
Future<Uint8List> assetBytes(Ref ref, String storageKey) =>
    ref.watch(workspaceSessionProvider).assetStore.readBytes(storageKey);

/// Search/filter state follows the workspace scope across sidebar and drawer.
@Riverpod(keepAlive: true)
class DocumentSearch extends _$DocumentSearch {
  @override
  String build() => '';
  void setQuery(String value) => state = value;
}

@Riverpod(keepAlive: true)
class MediaFilter extends _$MediaFilter {
  @override
  MediaKind? build() => null;
  void setKind(MediaKind? value) => state = value;
}

@Riverpod(keepAlive: true)
class MediaSearch extends _$MediaSearch {
  @override
  String build() => '';
  void setQuery(String value) => state = value;
}
