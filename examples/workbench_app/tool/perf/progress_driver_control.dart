import 'dart:async';
import 'dart:convert';

import 'progress_driver.dart';

/// Pure Dart calibration, with no workspace or widget work. The artificial
/// 500us consumer cost isolates pause/resume drift from product processing.
Future<void> main() async {
  final results = <Map<String, Object?>>[];
  for (final consumerCostUs in [0, 500]) {
    for (final mode in ['legacy', 'deadline']) {
      final driver = ProgressDriver(mode: mode);
      await for (final chunk in driver.open()) {
        if (chunk.length != 128) throw StateError('Unexpected chunk');
        if (consumerCostUs > 0) {
          final work = Stopwatch()..start();
          while (work.elapsedMicroseconds < consumerCostUs) {
            // Intentionally emulate bounded synchronous work per consumed event.
          }
        }
      }
      results.add({'consumerCostUs': consumerCostUs, ...driver.metrics});
    }
  }
  // ignore: avoid_print
  print(
    jsonEncode({
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'control':
          'No Flutter, IO, snapshot or app work; real wall-clock scheduling',
      'cases': results,
    }),
  );
}
