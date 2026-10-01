import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/window/workbench_window_chrome.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';

class WorkbenchApp extends StatefulWidget {
  const WorkbenchApp({super.key, required this.bootstrap});
  final WorkbenchBootstrap bootstrap;
  @override
  State<WorkbenchApp> createState() => _WorkbenchAppState();
}

class _WorkbenchAppState extends State<WorkbenchApp>
    with WidgetsBindingObserver {
  final _panels = KoiWorkbenchController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.bootstrap.session.save());
      unawaited(widget.bootstrap.preview.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _panels.dispose();
    unawaited(widget.bootstrap.disposeAsync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.bootstrap.container,
    child: _ThemedWorkbench(bootstrap: widget.bootstrap, panels: _panels),
  );
}

class _ThemedWorkbench extends ConsumerWidget {
  const _ThemedWorkbench({required this.bootstrap, required this.panels});
  final WorkbenchBootstrap bootstrap;
  final KoiWorkbenchController panels;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          themeMode:
              value.value?.snapshot.preferences.themeMode ??
              bootstrap.session.state.snapshot.preferences.themeMode,
          density:
              value.value?.snapshot.preferences.density ??
              bootstrap.session.state.snapshot.preferences.density,
        ),
      ),
    );
    final density = preferences.density == WorkspaceDensity.compact
        ? KoiDensity.compact
        : KoiDensity.comfortable;
    return MaterialApp.router(
      title: 'Koi 工作区',
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.build(density: density),
      darkTheme: AppTheme.build(brightness: Brightness.dark, density: density),
      themeMode: switch (preferences.themeMode) {
        WorkspaceThemeMode.system => ThemeMode.system,
        WorkspaceThemeMode.light => ThemeMode.light,
        WorkspaceThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: bootstrap.router,
      builder: (context, child) => ListenableBuilder(
        listenable: bootstrap.history,
        builder: (context, content) => _WindowChrome(
          panels: panels,
          canGoBack: bootstrap.history.canGoBack,
          canGoForward: bootstrap.history.canGoForward,
          onBack: bootstrap.history.goBack,
          onForward: bootstrap.history.goForward,
          onSave: () => unawaited(bootstrap.session.save()),
          child: content!,
        ),
        child: Column(
          children: [
            if (bootstrap.storageOwner.warning != null)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(bootstrap.storageOwner.warning!),
                ),
              ),
            Expanded(child: child ?? const SizedBox()),
          ],
        ),
      ),
    );
  }
}

/// Selecting only the visible title avoids rebuilding app themes for IO progress.
class _WindowChrome extends ConsumerWidget {
  const _WindowChrome({
    required this.panels,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onSave,
    required this.child,
  });
  final KoiWorkbenchController panels;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(navigationHistoryProvider);
    final session = ref.watch(workspaceSessionProvider);
    final path = history.current?.location.path ?? '/text';
    String titleOf(WorkspaceSnapshot snapshot) => switch (path) {
      '/text' =>
        snapshot.documents
                .where(
                  (document) =>
                      document.id == snapshot.preferences.selectedDocumentId,
                )
                .firstOrNull
                ?.title ??
            snapshot.documents.firstOrNull?.title ??
            '文本资料',
      '/media' =>
        snapshot.assets
                .where(
                  (asset) => asset.id == snapshot.preferences.selectedAssetId,
                )
                .firstOrNull
                ?.name ??
            '媒体素材',
      _ => '任务',
    };
    final title = ref.watch(
      workspaceStateProvider.select(
        (value) => titleOf(value.value?.snapshot ?? session.state.snapshot),
      ),
    );
    return WorkbenchWindowChrome(
      title: title,
      panels: panels,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      onBack: onBack,
      onForward: onForward,
      onSave: onSave,
      child: child,
    );
  }
}
