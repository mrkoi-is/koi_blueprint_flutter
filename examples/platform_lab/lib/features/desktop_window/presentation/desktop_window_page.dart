import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';

Widget buildDesktopWindowPage(BuildContext context) =>
    const DesktopWindowPage();

class DesktopWindowPage extends ConsumerWidget {
  const DesktopWindowPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(desktopWindowHostProvider);
    Future<void> retry() async {
      await initializeDesktopWindow();
      ref.invalidate(desktopWindowHostProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.platformDesktopWindow),
      ),
      body: host == null
          ? KoiErrorState(
              title: AppLocalizations.of(context)!.platformWindowUnavailable,
              onRetry: retry,
              description:
                  DesktopWindowRuntime.error ??
                  AppLocalizations.of(context)!.platformWindowUninitialized,
            )
          : ListenableBuilder(
              listenable: host,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    host.ready
                        ? AppLocalizations.of(context)!.platformGeometrySaved
                        : AppLocalizations.of(context)!.platformWindowFallback,
                  ),
                  if (host.error != null) SelectableText(host.error!),
                  if (!host.ready)
                    FilledButton(
                      onPressed: retry,
                      child: Text(AppLocalizations.of(context)!.settingsRetry),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: host.ready
                        ? () => unawaited(host.saveGeometry())
                        : null,
                    child: Text(
                      AppLocalizations.of(context)!.platformSaveGeometry,
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      AppLocalizations.of(context)!.platformCloseWindowToTray,
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)!.platformTrayRequirement,
                    ),
                    value: host.hideOnClose,
                    onChanged: host.trayAvailable
                        ? (value) => host.configureTray(
                            available: true,
                            closeToTray: value,
                          )
                        : null,
                  ),
                  OutlinedButton(
                    onPressed: host.ready ? () => unawaited(host.show()) : null,
                    child: Text(
                      AppLocalizations.of(context)!.platformShowWindow,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
