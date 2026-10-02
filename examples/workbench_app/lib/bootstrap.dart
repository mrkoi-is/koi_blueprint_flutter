import 'package:workbench_app/core/capabilities/installed_capabilities.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
import 'package:workbench_app/core/diagnostics/app_diagnostics.dart';
import 'package:workbench_app/features/workspace/presentation/providers/appearance_providers.dart';
import 'package:workbench_app/core/router/app_routes.dart';
import 'package:workbench_app/core/router/workbench_navigation_history.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';
import 'package:workbench_app/features/workspace/data/file_selector_import_port.dart';
import 'package:workbench_app/features/workspace/data/image_thumbnail.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage.dart'
    as storage;
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_preview_session.dart';

/// Composition root owns storage, one workspace, player owner and router.
final class WorkbenchBootstrap {
  WorkbenchBootstrap._(
    this.storageOwner,
    this.preferencesStore,
    this.session,
    this.preview,
    this.container,
    this.router,
    this.history,
    this._routeListener,
  );
  final storage.WorkspaceStorage storageOwner;
  final UiPreferencesStore preferencesStore;
  final WorkspaceSession session;
  final MediaPreviewSession preview;
  final ProviderContainer container;
  final GoRouter router;
  final WorkbenchNavigationHistory history;
  final void Function() _routeListener;
  Future<void>? _closing;
  Future<WorkspaceSaveResult>? _preparation;
  final preparingToClose = ValueNotifier<bool>(false);

  static Future<WorkbenchBootstrap> create({
    Future<storage.WorkspaceStorage> Function()? openStorage,
    FileImportPort? fileImportPort,
    MediaPlaybackFactory createPlayback = MediaKitPlayback.new,
    Future<Uint8List> Function(Uint8List)? encodeThumbnail,
    String? initialLocation,
    Future<UiPreferencesStore> Function()? openPreferences,
  }) async {
    storage.WorkspaceStorage? ownedStorage;
    UiPreferencesStore? ownedPreferences;
    WorkspaceSession? ownedSession;
    MediaPreviewSession? ownedPreview;
    ProviderContainer? ownedContainer;
    GoRouter? ownedRouter;
    WorkbenchNavigationHistory? ownedHistory;
    try {
      final preferencesStore =
          await (openPreferences?.call() ??
              Future.value(MemoryUiPreferencesStore()));
      ownedPreferences = preferencesStore;
      final data = await (openStorage ?? storage.openWorkspaceStorage)();
      ownedStorage = data;
      final encoder = encodeThumbnail ?? createImageThumbnail;
      final session = WorkspaceSession(
        repository: data.repository,
        assetStore: data.assetStore,
        fileImportPort: fileImportPort ?? FileSelectorImportPort(),
        imageThumbnail: (bytes) => encoder(Uint8List.fromList(bytes)),
      );
      ownedSession = session;
      await session.initialize();
      final preview = MediaPreviewSession(
        workspace: session,
        openSource: (key) async {
          final lease = await data.openPreview(key);
          return PreviewSource(uri: lease.uri, release: lease.dispose);
        },
        encodeThumbnail: encoder,
        createPlayback: createPlayback,
      );
      ownedPreview = preview;
      final restored = session.state.snapshot.preferences.navId;
      final location =
          initialLocation ??
          (['text', 'media', 'tasks'].contains(restored)
              ? '/$restored'
              : '/text');
      final router = GoRouter(
        routes: $appRoutes,
        initialLocation: location,
        redirect: (_, state) => state.uri.path == '/' ? '/text' : null,
      );
      ownedRouter = router;
      void routeListener() {
        final path = router.routeInformationProvider.value.uri.path;
        final navId = switch (path) {
          '/text' => 'text',
          '/media' => 'media',
          '/tasks' => 'tasks',
          _ => null,
        };
        final preferences = session.state.snapshot.preferences;
        if (navId != null && preferences.navId != navId) {
          session.updatePreferences(preferences.copyWith(navId: navId));
        }
        unawaited(preview.setVisible(path == '/media'));
      }

      router.routeInformationProvider.addListener(routeListener);
      routeListener();
      final history = WorkbenchNavigationHistory(
        router: router,
        workspace: session,
      );
      ownedHistory = history;
      final container = ProviderContainer(
        retry: (_, _) => null,
        observers: [AppDiagnostics.instance.observer],
        overrides: [
          uiPreferencesStoreProvider.overrideWithValue(preferencesStore),
          workspaceSessionProvider.overrideWithValue(session),
          mediaPreviewSessionProvider.overrideWithValue(preview),
          navigationHistoryProvider.overrideWithValue(history),
        ],
      );
      ownedContainer = container;
      return WorkbenchBootstrap._(
        data,
        preferencesStore,
        session,
        preview,
        container,
        router,
        history,
        routeListener,
      );
    } catch (failure, trace) {
      final failures = <Object>[failure];
      for (final close in <FutureOr<void> Function()>[
        if (ownedHistory != null) ownedHistory.disposeAsync,
        if (ownedRouter != null) ownedRouter.dispose,
        if (ownedContainer != null) ownedContainer.dispose,
        if (ownedPreview != null) ownedPreview.disposeAsync,
        if (ownedSession != null) ownedSession.dispose,
        if (ownedStorage != null) ownedStorage.close,
        if (ownedPreferences != null) ownedPreferences.close,
      ]) {
        try {
          await close();
        } catch (error) {
          failures.add(error);
        }
      }
      Error.throwWithStackTrace(
        failures.length == 1 ? failure : WorkbenchCleanupException(failures),
        trace,
      );
    }
  }

  Future<WorkspaceSaveResult> prepareToClose() =>
      _preparation ??= _prepareToClose();
  Future<WorkspaceSaveResult> _prepareToClose() async {
    preparingToClose.value = true;
    try {
      if (container.exists(workbenchAppearanceProvider) &&
          !await container.read(workbenchAppearanceProvider.notifier).flush()) {
        preparingToClose.value = false;
        _preparation = null;
        return const WorkspaceSaveResult.failed(
          'App preferences could not be saved',
        );
      }
      if (!await prepareInstalledCapabilities()) {
        preparingToClose.value = false;
        _preparation = null;
        return const WorkspaceSaveResult.failed(
          'Capability close preparation failed',
        );
      }
      await preview.prepareToClose();
      final result = await session.prepareToClose();
      if (!result.succeeded) {
        preparingToClose.value = false;
        _preparation = null;
      }
      return result;
    } catch (error) {
      preparingToClose.value = false;
      _preparation = null;
      return WorkspaceSaveResult.failed('关闭前收尾失败：$error');
    }
  }

  Future<void> disposeAsync() => _closing ??= _close();
  Future<void> _close() async {
    router.routeInformationProvider.removeListener(_routeListener);
    final failures = <Object>[];
    for (final close in <FutureOr<void> Function()>[
      history.disposeAsync,
      router.dispose,
      container.dispose,
      preview.disposeAsync,
      session.dispose,
      storageOwner.close,
      preferencesStore.close,
      disposeInstalledCapabilities,
      preparingToClose.dispose,
    ]) {
      try {
        await close();
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw WorkbenchCleanupException(failures);
    }
  }
}

final class WorkbenchCleanupException implements Exception {
  const WorkbenchCleanupException(this.failures);
  final List<Object> failures;
  @override
  String toString() => '工作区清理失败：${failures.join('; ')}';
}
