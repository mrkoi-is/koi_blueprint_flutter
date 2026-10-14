import 'package:showcase_alpha/showcase_alpha.dart' show alphaMessage;
import 'package:showcase_beta/showcase_beta.dart' show betaMessage;
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:module_showcase/app.dart';
import 'package:module_showcase/bootstrap.dart';

@Dependencies([alphaMessage, betaMessage])
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await ShowcaseBootstrap.create();
  runApp(ProviderScope(child: ModuleShowcaseApp(bootstrap: bootstrap)));
}
