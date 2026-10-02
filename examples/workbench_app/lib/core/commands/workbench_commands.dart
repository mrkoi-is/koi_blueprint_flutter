import 'package:koi_core/koi_core.dart';

import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/l10n/app_strings.dart';

enum WorkbenchCommandId {
  save,
  importFiles,
  back,
  forward,
  toggleSidebar,
  toggleDetail,
  quit,
}

class WorkbenchCommandIntent extends Intent {
  const WorkbenchCommandIntent(this.id);
  final WorkbenchCommandId id;
}

/// Adapts existing owners to every UI entry point. It owns no workspace data.
class WorkbenchCommands extends ChangeNotifier {
  WorkbenchCommands({
    required this.bootstrap,
    required this.panels,
    Future<void> Function()? requestExit,
  }) : _requestExit = requestExit ?? _exit {
    bootstrap.history.addListener(notifyListeners);
    bootstrap.preparingToClose.addListener(notifyListeners);
    panels.addListener(notifyListeners);
  }
  final WorkbenchBootstrap bootstrap;
  final KoiWorkbenchController panels;
  final Future<void> Function() _requestExit;
  static Future<void> _exit() async {
    // didRequestAppExit remains the single durable-save/disposal protocol.
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }

  bool enabled(WorkbenchCommandId id) {
    if (bootstrap.preparingToClose.value) return false;
    return switch (id) {
      WorkbenchCommandId.back => bootstrap.history.canGoBack,
      WorkbenchCommandId.forward => bootstrap.history.canGoForward,
      WorkbenchCommandId.toggleSidebar => panels.canToggleSidebar,
      WorkbenchCommandId.toggleDetail => panels.canToggleDetail,
      WorkbenchCommandId.importFiles =>
        bootstrap.session.state.initialized &&
            const {
              '/text',
              '/media',
            }.contains(bootstrap.history.current?.location.path),
      WorkbenchCommandId.save => bootstrap.session.state.initialized,
      WorkbenchCommandId.quit => true,
    };
  }

  /// Returns false when the latest state no longer permits the requested action.
  Future<bool> invoke(WorkbenchCommandId id) async {
    if (!enabled(id)) return false;
    switch (id) {
      case WorkbenchCommandId.save:
        final saved = (await bootstrap.session.save()).succeeded;
        if (saved) await CapabilityNavigation.instance.retry();
        return saved;
      case WorkbenchCommandId.importFiles:
        await bootstrap.session.importFiles(
          bootstrap.history.current?.location.path == '/media'
              ? ImportKind.media
              : ImportKind.text,
        );
      case WorkbenchCommandId.back:
        bootstrap.history.goBack();
      case WorkbenchCommandId.forward:
        bootstrap.history.goForward();
      case WorkbenchCommandId.toggleSidebar:
        panels.toggleSidebar();
      case WorkbenchCommandId.toggleDetail:
        panels.toggleDetail();
      case WorkbenchCommandId.quit:
        await _requestExit();
    }
    return true;
  }

  static String label(
    BuildContext context,
    WorkbenchCommandId id,
  ) => switch (id) {
    WorkbenchCommandId.save => context.l10n.save,
    WorkbenchCommandId.importFiles => context.l10n.importFiles,
    WorkbenchCommandId.back => context.l10n.back,
    WorkbenchCommandId.forward => context.l10n.forward,
    WorkbenchCommandId.toggleSidebar => KoiUiStrings.of(context).toggleSidebar,
    WorkbenchCommandId.toggleDetail => KoiUiStrings.of(context).toggleDetail,
    WorkbenchCommandId.quit => context.l10n.quit,
  };

  static SingleActivator? shortcut(
    WorkbenchCommandId id,
    TargetPlatform platform,
  ) {
    final mac = platform == TargetPlatform.macOS;
    return switch (id) {
      WorkbenchCommandId.save => SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: mac,
        control: !mac,
      ),
      WorkbenchCommandId.importFiles => SingleActivator(
        LogicalKeyboardKey.keyO,
        meta: mac,
        control: !mac,
      ),
      WorkbenchCommandId.back =>
        mac
            ? const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)
            : const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
      WorkbenchCommandId.forward =>
        mac
            ? const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true)
            : const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true),
      _ => null,
    };
  }

  static Map<ShortcutActivator, Intent> bindings(TargetPlatform platform) {
    final bindings = <ShortcutActivator, Intent>{};
    for (final id in WorkbenchCommandId.values) {
      final activator = shortcut(id, platform);
      if (activator != null) bindings[activator] = WorkbenchCommandIntent(id);
    }
    // Preserve the existing Mac-compatible aliases on external keyboards.
    for (final id in [
      WorkbenchCommandId.save,
      WorkbenchCommandId.importFiles,
      WorkbenchCommandId.back,
      WorkbenchCommandId.forward,
    ]) {
      bindings[shortcut(id, TargetPlatform.macOS)!] = WorkbenchCommandIntent(
        id,
      );
    }
    return bindings;
  }

  static String shortcutLabel(SingleActivator shortcut) => [
    if (shortcut.meta) '⌘',
    if (shortcut.control) 'Ctrl',
    if (shortcut.alt) 'Alt',
    if (shortcut.shift) 'Shift',
    shortcut.trigger.keyLabel,
  ].join(' + ');

  @override
  void dispose() {
    bootstrap.history.removeListener(notifyListeners);
    bootstrap.preparingToClose.removeListener(notifyListeners);
    panels.removeListener(notifyListeners);
    super.dispose();
  }
}

class WorkbenchCommandScope extends InheritedNotifier<WorkbenchCommands> {
  const WorkbenchCommandScope({
    required WorkbenchCommands commands,
    required super.child,
    super.key,
  }) : super(notifier: commands);
  static WorkbenchCommands of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkbenchCommandScope>()!
      .notifier!;
}
