import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkbenchLauncher());
}

/// Both decoder initialization and storage failures are handled by the launcher.
Future<WorkbenchBootstrap> initializeWorkbench() async {
  MediaKit.ensureInitialized();
  return WorkbenchBootstrap.create();
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
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: value.hasError
              ? KoiErrorState(
                  title: '工作区初始化失败',
                  description: '${value.error}',
                  onRetry: () {
                    final pending = _create();
                    setState(() {
                      _pending = pending;
                    });
                  },
                )
              : const KoiLoadingState(message: '正在初始化本地工作区…'),
        ),
      );
    },
  );
}
