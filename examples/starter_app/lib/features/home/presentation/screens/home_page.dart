import 'package:starter_app/core/diagnostics/diagnostic_version.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:koi_core/koi_core.dart';
import 'package:starter_app/core/capabilities/app_capabilities.dart';
import 'package:starter_app/core/router/app_routes.dart';
import 'package:starter_app/l10n/generated/app_localizations.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Starter App'),
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context)!.aboutTitle,
          icon: const Icon(Icons.info_outline),
          onPressed: () {
            final strings = AppLocalizations.of(context)!;
            const info = BuildInfo.current;
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AboutDialog(
                applicationName: 'Starter App',

                children: [
                  DiagnosticVersion(
                    version: '${info.version}+${info.build}',
                    onUnlocked:
                        appCapabilities.any((c) => c.id == 'diagnostics')
                        ? () {
                            Navigator.pop(dialogContext);
                            const CapabilityRoute(id: 'diagnostics')
                                .push<void>(context);
                          }
                        : null,
                  ),
                  SelectableText(
                    '${strings.aboutSource}: ${info.source}\n'
                    '${strings.aboutChannel}: ${info.channel}\n'
                    '${strings.aboutPlatform}: ${info.platform} / ${info.architecture}',
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(child: Text(AppLocalizations.of(context)!.ready)),
        for (final capability in appCapabilities.where(
          (c) => !kReleaseMode || c.id != 'diagnostics',
        ))
          ListTile(
            title: Text(capability.titleFor(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => CapabilityRoute(id: capability.id).push<void>(context),
          ),
      ],
    ),
  );
}
