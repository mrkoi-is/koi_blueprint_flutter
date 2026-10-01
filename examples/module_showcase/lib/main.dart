import 'package:flutter/widgets.dart';
import 'package:module_showcase/app.dart';
import 'package:module_showcase/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await ShowcaseBootstrap.create();
  runApp(ModuleShowcaseApp(bootstrap: bootstrap));
}
