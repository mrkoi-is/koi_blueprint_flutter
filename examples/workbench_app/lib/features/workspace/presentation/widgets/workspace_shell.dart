import 'package:workbench_app/core/preferences/appearance_providers.dart';
import 'package:workbench_app/core/commands/workbench_commands.dart';
import 'package:workbench_app/core/capabilities/app_capabilities.dart';
import 'package:workbench_app/core/router/app_routes.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/appearance_dialog.dart';
import 'package:workbench_app/l10n/app_strings.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/core/window/workbench_window_chrome.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/widgets/workspace_panels.dart';

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  final _panelStorage = PageStorageBucket();
  StatefulNavigationShell get navigationShell => widget.navigationShell;
  static const _ids = ['text', 'media', 'tasks'];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workspaceSessionProvider);
    final appearance = ref.watch(appAppearanceProvider).value;
    final appearanceActions = ref.read(appAppearanceProvider.notifier);
    final commands = WorkbenchCommandScope.of(context);
    final history = ref.watch(navigationHistoryProvider);
    final nativeToolbar = WorkbenchWindowInfo.nativeToolbarOf(context);
    final state = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          saving: value.value?.saving ?? session.state.saving,
          error: value.value?.error ?? session.state.error,
          initialized: value.value?.initialized ?? session.state.initialized,
          density:
              value.value?.snapshot.preferences.density ??
              session.state.snapshot.preferences.density,
          sidebarWidth:
              value.value?.snapshot.preferences.sidebarWidth ??
              session.state.snapshot.preferences.sidebarWidth,
          detailsWidth:
              value.value?.snapshot.preferences.detailsWidth ??
              session.state.snapshot.preferences.detailsWidth,
        ),
      ),
    );
    WorkspacePreferences preferences() => session.state.snapshot.preferences;
    final effectiveTheme =
        appearance?.themeMode ??
        switch (preferences().themeMode) {
          WorkspaceThemeMode.system => ThemeMode.system,
          WorkspaceThemeMode.light => ThemeMode.light,
          WorkspaceThemeMode.dark => ThemeMode.dark,
        };
    final compact = KoiThemeTokens.of(context).density == KoiDensity.compact;
    void changeTheme(WorkspaceThemeMode mode) {
      appearanceActions.setThemeMode(switch (mode) {
        WorkspaceThemeMode.system => ThemeMode.system,
        WorkspaceThemeMode.light => ThemeMode.light,
        WorkspaceThemeMode.dark => ThemeMode.dark,
      });
      session.updatePreferences(preferences().copyWith(themeMode: mode));
    }

    return Shortcuts(
      shortcuts: WorkbenchCommands.bindings(defaultTargetPlatform),
      child: Actions(
        actions: {
          WorkbenchCommandIntent: CallbackAction<WorkbenchCommandIntent>(
            onInvoke: (intent) {
              unawaited(commands.invoke(intent.id));
              return null;
            },
          ),
        },
        child: KoiWorkbenchFrame(
          controller: WorkbenchWindowInfo.panelsOf(context),
          sidebar: PageStorage(
            bucket: _panelStorage,
            child: WorkspaceSidebar(index: navigationShell.currentIndex),
          ),
          // Each route supplies a detail surface only when it has useful data.
          // The task page already presents its explanations and job status.
          detail: navigationShell.currentIndex == 2
              ? null
              : PageStorage(
                  bucket: _panelStorage,
                  child: WorkspaceDetails(index: navigationShell.currentIndex),
                ),
          sidebarWidth: state.sidebarWidth,
          detailWidth: state.detailsWidth,
          onSidebarWidthChanged: (width) => session.updatePreferences(
            preferences().copyWith(sidebarWidth: width),
          ),
          onDetailWidthChanged: (width) => session.updatePreferences(
            preferences().copyWith(detailsWidth: width),
          ),
          showHeader: !nativeToolbar,
          title: nativeToolbar
              ? null
              : Text(
                  WorkbenchWindowInfo.titleOf(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          headerLeading: nativeToolbar
              ? null
              : ListenableBuilder(
                  listenable: history,
                  builder: (context, _) => KoiNavigationHistoryControls(
                    onBack: commands.enabled(WorkbenchCommandId.back)
                        ? () => unawaited(
                            commands.invoke(WorkbenchCommandId.back),
                          )
                        : null,
                    onForward: commands.enabled(WorkbenchCommandId.forward)
                        ? () => unawaited(
                            commands.invoke(WorkbenchCommandId.forward),
                          )
                        : null,
                  ),
                ),
          destinations: [
            KoiNavigationDestination(
              id: 'text',
              label: context.l10n.text,
              icon: Icons.description_outlined,
            ),
            KoiNavigationDestination(
              id: 'media',
              label: context.l10n.media,
              icon: Icons.perm_media_outlined,
            ),
            KoiNavigationDestination(
              id: 'tasks',
              label: context.l10n.tasks,
              icon: Icons.task_alt_outlined,
            ),
          ],
          selectedId: _ids[navigationShell.currentIndex],
          onDestinationSelected: (id) {
            session.updatePreferences(preferences().copyWith(navId: id));
            navigationShell.goBranch(_ids.indexOf(id));
          },
          navigationTrailing: Tooltip(
            message: context.l10n.settings,
            child: KoiMenu(
              key: const ValueKey('workspace-settings'),
              label: context.l10n.settings,
              items: [
                KoiMenuItem(
                  label: context.l10n.aboutTitle,
                  icon: Icons.info_outline,
                  onSelected: () {
                    const info = BuildInfo.current;
                    showAboutDialog(
                      context: context,
                      applicationName: context.l10n.appTitle,
                      applicationVersion: '${info.version}+${info.build}',
                      children: [
                        SelectableText(
                          '${context.l10n.aboutSource}: ${info.source}\n'
                          '${context.l10n.aboutChannel}: ${info.channel}\n'
                          '${context.l10n.aboutPlatform}: ${info.platform} / ${info.architecture}',
                        ),
                      ],
                    );
                  },
                ),
                KoiMenuItem(
                  label: '${context.l10n.language} / ${context.l10n.accent}',
                  icon: Icons.palette_outlined,
                  onSelected: () =>
                      unawaited(showAppearanceDialog(context, ref)),
                ),
                KoiMenuItem(
                  label: context.l10n.keyboardShortcuts,
                  icon: Icons.keyboard_outlined,
                  onSelected: () => unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.l10n.keyboardShortcuts),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final id in WorkbenchCommandId.values)
                              if (WorkbenchCommands.shortcut(
                                    id,
                                    defaultTargetPlatform,
                                  )
                                  case final shortcut?)
                                ListTile(
                                  title: Text(
                                    WorkbenchCommands.label(context, id),
                                  ),
                                  trailing: Text(
                                    WorkbenchCommands.shortcutLabel(shortcut),
                                  ),
                                ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(context.l10n.confirm),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final capability in appCapabilities)
                  KoiMenuItem(
                    label: capability.titleFor(context),
                    onSelected: () =>
                        CapabilityRoute(id: capability.id).push<void>(context),
                  ),
                for (final id in [
                  WorkbenchCommandId.save,
                  WorkbenchCommandId.importFiles,
                  WorkbenchCommandId.back,
                  WorkbenchCommandId.forward,
                  WorkbenchCommandId.quit,
                ])
                  KoiMenuItem(
                    label: WorkbenchCommands.label(context, id),
                    enabled: commands.enabled(id),
                    shortcut: WorkbenchCommands.shortcut(
                      id,
                      defaultTargetPlatform,
                    ),
                    onSelected: () => unawaited(commands.invoke(id)),
                  ),
                for (final item in <(String, WorkspaceThemeMode, ThemeMode)>[
                  (
                    context.l10n.systemTheme,
                    WorkspaceThemeMode.system,
                    ThemeMode.system,
                  ),
                  (
                    context.l10n.lightTheme,
                    WorkspaceThemeMode.light,
                    ThemeMode.light,
                  ),
                  (
                    context.l10n.darkTheme,
                    WorkspaceThemeMode.dark,
                    ThemeMode.dark,
                  ),
                ])
                  KoiMenuItem(
                    label: item.$1,
                    checked: effectiveTheme == item.$3,
                    onSelected: () => changeTheme(item.$2),
                  ),
                KoiMenuItem(
                  label: compact
                      ? context.l10n.comfortable
                      : context.l10n.compact,
                  onSelected: () {
                    appearanceActions.setDensity(
                      compact ? KoiDensity.comfortable : KoiDensity.compact,
                    );
                    session.updatePreferences(
                      preferences().copyWith(
                        density: compact
                            ? WorkspaceDensity.comfortable
                            : WorkspaceDensity.compact,
                      ),
                    );
                  },
                ),
              ],
              child: const Icon(Icons.settings_outlined),
            ),
          ),
          actions: [
            if (state.saving && !nativeToolbar)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (!nativeToolbar)
              IconButton(
                tooltip: context.l10n.saveShortcut,
                icon: const Icon(Icons.save_outlined),
                onPressed: commands.enabled(WorkbenchCommandId.save)
                    ? () => unawaited(commands.invoke(WorkbenchCommandId.save))
                    : null,
              ),
          ],
          body: Column(
            children: [
              if (state.error != null)
                MaterialBanner(
                  content: Text(state.error!),
                  actions: [
                    TextButton(
                      onPressed: () => unawaited(
                        state.initialized
                            ? session.save()
                            : session.initialize(),
                      ),
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ),
              Expanded(
                child: !state.initialized
                    ? KoiLoadingState(message: context.l10n.restoring)
                    : navigationShell,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
