import 'package:flutter/foundation.dart';
import 'package:koi_core/koi_core.dart';

final class DiagnosticLan extends ChangeNotifier {
  DiagnosticLan(this.store);
  final BoundedDiagnosticStore Function() store;
  bool? notificationGranted;
  bool? batteryOptimizationIgnored;
  bool get supported => false;
  bool get running => false;
  bool get busy => false;
  String? get address => null;
  String? get credential => null;
  Object? get error => null;
  Future<List<String>> interfaces() async => [];
  Future<void> start({String? address, String language = 'en'}) async =>
      throw UnsupportedError('LAN hosting requires a native platform');
  Future<void> stop() async {}
  Future<void> close() async {
    dispose();
  }
}
