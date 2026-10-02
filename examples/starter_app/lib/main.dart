import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:starter_app/app.dart';
import 'package:starter_app/core/capabilities/installed_capabilities.dart';
import 'package:starter_app/core/diagnostics/app_diagnostics.dart';
import 'package:starter_app/l10n/generated/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.instance.install();
  runApp(const StarterLauncher());
}

class StarterLauncher extends StatefulWidget {
  const StarterLauncher({
    super.key,
    this.initialize = initializeInstalledCapabilities,
  });
  final Future<void> Function() initialize;
  @override
  State<StarterLauncher> createState() => _StarterLauncherState();
}

class _StarterLauncherState extends State<StarterLauncher> {
  late Future<void> _pending;
  @override
  void initState() {
    super.initState();
    _pending = _initialize();
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
      if (!mounted) await disposeInstalledCapabilities();
    } catch (error, stack) {
      AppDiagnostics.instance.record(error, stack, 'bootstrap');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _pending,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.done && !state.hasError) {
        return ProviderScope(
          observers: [AppDiagnostics.instance.observer],
          child: const StarterApp(),
        );
      }
      return MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          KoiUiLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: resolveKoiLocale,
        home: Builder(
          builder: (context) {
            final strings = AppLocalizations.of(context)!;
            return Scaffold(
              body: state.hasError
                  ? KoiErrorState(
                      title: strings.initializationFailed,
                      description: '${state.error}',
                      onRetry: () => setState(() => _pending = _initialize()),
                    )
                  : KoiLoadingState(message: strings.initializing),
            );
          },
        ),
      );
    },
  );
}
