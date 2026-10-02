import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:network_lab/app.dart';
import 'package:network_lab/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment(
    'NETWORK_LAB_URL',
    defaultValue: 'http://127.0.0.1:8765/',
  );
  try {
    final bootstrap = await NetworkBootstrap.create(
      baseUri: Uri.parse(endpoint),
    );
    runApp(NetworkLabApp(bootstrap: bootstrap));
  } catch (error) {
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: Text('Network Lab 无法启动：$error'))),
      ),
    );
  }
}
