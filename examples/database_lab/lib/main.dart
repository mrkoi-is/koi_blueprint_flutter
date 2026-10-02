import 'package:database_lab/l10n/generated/app_localizations.dart';

import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:database_lab/capability.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Database Lab',
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _StandaloneOwner(),
    ),
  );
}

class _StandaloneOwner extends StatefulWidget {
  const _StandaloneOwner();
  @override
  State<_StandaloneOwner> createState() => _StandaloneOwnerState();
}

class _StandaloneOwnerState extends State<_StandaloneOwner> {
  late final AppLifecycleListener _lifecycle;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        if (!await CapabilityLifecycle.instance.prepare()) {
          return AppExitResponse.cancel;
        }
        await CapabilityLifecycle.instance.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DatabaseLabBootstrap();
}
