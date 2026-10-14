import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:koi_core/koi_core.dart' show CapabilityLifecycle;
import 'package:network_lab/bootstrap.dart';

class NetworkLabApp extends StatefulWidget {
  const NetworkLabApp({required this.bootstrap, this.locale, super.key});
  final Locale? locale;
  final NetworkBootstrap bootstrap;
  @override
  State<NetworkLabApp> createState() => _NetworkLabAppState();
}

class _NetworkLabAppState extends State<NetworkLabApp> {
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
        await widget.bootstrap.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(widget.bootstrap.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.bootstrap.container,
    child: MaterialApp.router(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)!.networkLabTitle,
      locale: widget.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: widget.bootstrap.router,
    ),
  );
}
