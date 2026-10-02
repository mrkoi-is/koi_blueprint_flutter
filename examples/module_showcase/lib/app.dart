import 'package:module_showcase/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:module_showcase/bootstrap.dart';

class ModuleShowcaseApp extends StatefulWidget {
  const ModuleShowcaseApp({super.key, required this.bootstrap});

  final ShowcaseBootstrap bootstrap;

  @override
  State<ModuleShowcaseApp> createState() => _ModuleShowcaseAppState();
}

class _ModuleShowcaseAppState extends State<ModuleShowcaseApp> {
  @override
  void dispose() {
    unawaited(widget.bootstrap.disposeAsync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.bootstrap.container,
    child: MaterialApp.router(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: widget.bootstrap.router,
    ),
  );
}
