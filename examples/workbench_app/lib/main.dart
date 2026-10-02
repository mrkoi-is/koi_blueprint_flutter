import 'package:workbench_app/core/diagnostics/app_diagnostics.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
import 'package:workbench_app/core/capabilities/installed_capabilities.dart';
import 'package:workbench_app/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.instance.install();
  runApp(const WorkbenchLauncher());
}

/// Both decoder initialization and storage failures are handled by the launcher.
Future<WorkbenchBootstrap> initializeWorkbench() async {
  await initializeInstalledCapabilities();
  try {
    MediaKit.ensureInitialized();
    return await WorkbenchBootstrap.create(
      openPreferences: openUiPreferencesStore,
    );
  } catch (error, stack) {
    AppDiagnostics.instance.record(error, stack, 'bootstrap');
    try {
      await disposeInstalledCapabilities();
    } catch (cleanup, trace) {
      AppDiagnostics.instance.record(cleanup, trace, 'bootstrap.cleanup');
    }
    rethrow;
  }
}

class WorkbenchLauncher extends StatefulWidget {
  const WorkbenchLauncher({
    super.key,
    this.createBootstrap = initializeWorkbench,
  });
  final Future<WorkbenchBootstrap> Function() createBootstrap;
  @override
  State<WorkbenchLauncher> createState() => _WorkbenchLauncherState();
}

class _WorkbenchLauncherState extends State<WorkbenchLauncher> {
  late Future<WorkbenchBootstrap> _pending;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _pending = _create();
  }

  Future<WorkbenchBootstrap> _create() async {
    final generation = ++_generation;
    final bootstrap = await widget.createBootstrap();
    if (!mounted || generation != _generation) {
      await bootstrap.disposeAsync();
      throw StateError('初始化已取消');
    }
    return bootstrap;
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkbenchBootstrap>(
    future: _pending,
    builder: (context, value) {
      final bootstrap = value.data;
      if (bootstrap != null) {
        return WorkbenchApp(bootstrap: bootstrap);
      }
      return MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          KoiUiLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: resolveKoiLocale,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: value.hasError
                ? KoiErrorState(
                    title: value.error is WorkspaceInUse
                        ? context.l10n.workspaceInUse
                        : context.l10n.initializationFailed,
                    description: '${value.error}',
                    onRetry: () {
                      final pending = _create();
                      setState(() {
                        _pending = pending;
                      });
                    },
                  )
                : KoiLoadingState(message: context.l10n.initializing),
          ),
        ),
      );
    },
  );
}
