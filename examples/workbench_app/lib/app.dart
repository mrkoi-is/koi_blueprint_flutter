import 'package:koi_core/koi_core.dart';
import 'package:workbench_app/core/capabilities/app_capabilities.dart';
import 'package:workbench_app/core/commands/workbench_commands.dart';
import 'package:workbench_app/l10n/app_strings.dart';
import 'package:workbench_app/core/preferences/appearance_providers.dart';

import 'dart:async';
import 'dart:ui' show AppExitResponse;

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
  late final WorkbenchCommands _commands;
  late final void Function() _detachNavigation;
  @override
  void initState() {
    super.initState();
    _commands = WorkbenchCommands(bootstrap: widget.bootstrap, panels: _panels);
    WidgetsBinding.instance.addObserver(this);
    _detachNavigation = CapabilityNavigation.instance.attach((id) async {
      if (!mounted || widget.bootstrap.preparingToClose.value) return false;
      if (!appCapabilities.any((capability) => capability.id == id)) {
        return true;
      }
      final location = '/capabilities/$id';
      if (widget.bootstrap.router.routeInformationProvider.value.uri.path ==
          location) {
        return true;
      }
      final saved = await widget.bootstrap.session.save();
      if (!saved.succeeded ||
          !mounted ||
          widget.bootstrap.preparingToClose.value) {
        return false;
      }
      widget.bootstrap.router.go(location);
      return true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (!widget.bootstrap.preparingToClose.value) {
        unawaited(widget.bootstrap.session.save());
      }
      unawaited(widget.bootstrap.preview.pause());
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final result = await widget.bootstrap.prepareToClose();
    if (!result.succeeded) return AppExitResponse.cancel;
    // Destruction is irreversible; a cleanup error after a successful save is
    // reported, but must not leave a destroyed window pretending to be usable.
    try {
      await widget.bootstrap.disposeAsync();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          context: ErrorDescription('关闭已保存的工作区'),
        ),
      );
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachNavigation();
    _commands.dispose();
    _panels.dispose();
    unawaited(widget.bootstrap.disposeAsync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.bootstrap.container,
    child: ValueListenableBuilder<bool>(
      valueListenable: widget.bootstrap.preparingToClose,
      builder: (_, closing, child) => ExcludeFocus(
        excluding: closing,
        child: AbsorbPointer(absorbing: closing, child: child),
      ),
      child: WorkbenchCommandScope(
        commands: _commands,
        child: _ThemedWorkbench(
          bootstrap: widget.bootstrap,
          panels: _panels,
          commands: _commands,
        ),
      ),
    ),
  );
}

class _ThemedWorkbench extends ConsumerWidget {
  const _ThemedWorkbench({
    required this.bootstrap,
    required this.panels,
    required this.commands,
  });
  final WorkbenchCommands commands;
  final WorkbenchBootstrap bootstrap;
  final KoiWorkbenchController panels;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(workbenchAppearanceProvider).value;
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
    final density =
        appearance?.density ??
        (preferences.density == WorkspaceDensity.compact
            ? KoiDensity.compact
            : KoiDensity.comfortable);
    return KoiInputDensity(
      density: appearance?.automaticDensity == true ? null : (density),
      builder: (context, effectiveDensity) => MaterialApp.router(
        onGenerateTitle: (context) => context.l10n.appTitle,
        themeAnimationDuration: Duration.zero,
        theme: AppTheme.build(
          density: effectiveDensity,
          accent: appearance?.accent ?? KoiAccent.moss,
        ),
        darkTheme: AppTheme.build(
          brightness: Brightness.dark,
          density: effectiveDensity,
          accent: appearance?.accent ?? KoiAccent.moss,
        ),
        themeMode:
            appearance?.themeMode ??
            switch (preferences.themeMode) {
              WorkspaceThemeMode.system => ThemeMode.system,
              WorkspaceThemeMode.light => ThemeMode.light,
              WorkspaceThemeMode.dark => ThemeMode.dark,
            },
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          KoiUiLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: resolveKoiLocale,
        locale: appearance?.locale,
        routerConfig: bootstrap.router,
        builder: (context, child) => ListenableBuilder(
          listenable: commands,
          builder: (context, content) => _WindowChrome(
            panels: panels,
            canExecuteCommand: () => !bootstrap.preparingToClose.value,
            canGoBack: bootstrap.history.canGoBack,
            canGoForward: bootstrap.history.canGoForward,
            onBack: () => unawaited(commands.invoke(WorkbenchCommandId.back)),
            onForward: () =>
                unawaited(commands.invoke(WorkbenchCommandId.forward)),
            onSave: () => unawaited(commands.invoke(WorkbenchCommandId.save)),
            onToggleSidebar: () =>
                unawaited(commands.invoke(WorkbenchCommandId.toggleSidebar)),
            onToggleDetail: () =>
                unawaited(commands.invoke(WorkbenchCommandId.toggleDetail)),
            child: content!,
          ),
          child: Column(
            children: [
              if (appearance?.saveError != null)
                MaterialBanner(
                  content: Text(appearance!.saveError!),
                  actions: [
                    TextButton(
                      onPressed: () => ref
                          .read(workbenchAppearanceProvider.notifier)
                          .retry(),
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ),
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
    required this.onToggleSidebar,
    required this.onToggleDetail,
    required this.canExecuteCommand,
    required this.child,
  });
  final KoiWorkbenchController panels;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onSave;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleDetail;
  final bool Function() canExecuteCommand;
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
            context.l10n.text,
      '/media' =>
        snapshot.assets
                .where(
                  (asset) => asset.id == snapshot.preferences.selectedAssetId,
                )
                .firstOrNull
                ?.name ??
            context.l10n.media,
      _ => context.l10n.tasks,
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
      onToggleSidebar: onToggleSidebar,
      onToggleDetail: onToggleDetail,
      canExecuteCommand: canExecuteCommand,
      child: child,
    );
  }
}
