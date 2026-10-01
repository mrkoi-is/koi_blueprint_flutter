import 'package:flutter/material.dart';
import 'package:koi_admin_app/bootstrap.dart';
import 'package:koi_admin_app/core/bootstrap/bootstrap_failure_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await bootstrap();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'koi_admin_app bootstrap',
      ),
    );
    runApp(BootstrapFailureApp(error: error));
  }
}
