import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';

import 'package:platform_lab/features/tray/presentation/providers/tray_providers.dart';

Widget buildTrayPage(BuildContext context) => const TrayPage();

class TrayPage extends ConsumerWidget {
  const TrayPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(trayPortProvider);
    final host = ref.watch(desktopWindowHostProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.platformSystemTray),
      ),
      body: host == null
          ? KoiErrorState(
              title: AppLocalizations.of(context)!.platformTrayUnavailable,
              description:
                  TrayRuntime.error ??
                  DesktopWindowRuntime.error ??
                  AppLocalizations.of(context)!.platformDesktopRequired,
            )
          : ListenableBuilder(
              listenable: host,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    host.trayAvailable
                        ? AppLocalizations.of(context)!.platformTrayDescription
                        : TrayRuntime.error ??
                              AppLocalizations.of(context)!
                                  .platformTrayUnavailable,
                  ),
                  SwitchListTile(
                    title: Text(
                      AppLocalizations.of(context)!.platformCloseToTray,
                    ),
                    value: host.hideOnClose,
                    onChanged: host.trayAvailable
                        ? (value) => host.configureTray(
                            available: true,
                            closeToTray: value,
                          )
                        : null,
                  ),
                  if (!host.trayAvailable)
                    FilledButton(
                      onPressed: () async {
                        await initializeTray();
                        if (context.mounted) {
                          ref.invalidate(desktopWindowHostProvider);
                          ref.invalidate(trayPortProvider);
                        }
                      },
                      child: Text(
                        AppLocalizations.of(context)!.platformTrayRetry,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
