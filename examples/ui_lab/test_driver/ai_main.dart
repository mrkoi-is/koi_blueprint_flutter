// Explicit debug entrypoint; the normal App never enables the driver extension.
import 'package:flutter_driver/driver_extension.dart';
import 'package:ui_lab/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
