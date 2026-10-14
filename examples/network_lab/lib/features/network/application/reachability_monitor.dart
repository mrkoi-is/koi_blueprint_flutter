import 'dart:async';

import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

/// A successful health probe is only a reachability hint, never API success.
final class ReachabilityMonitor {
  ReachabilityMonitor(
    this.transport,
    this.uri,
    this.onChanged, {
    this.interval = const Duration(seconds: 5),
  });
  final HttpTransport transport;
  final Uri uri;
  final void Function(Reachability) onChanged;
  final Duration interval;
  Timer? _timer;
  Cancellation? _probe;
  bool _active = false;
  bool _closed = false;
  int _generation = 0;
  void setActive(bool active) {
    if (_closed || _active == active) return;
    _active = active;
    _generation++;
    _timer?.cancel();
    _probe?.cancel();
    if (active) unawaited(probe());
  }

  Future<void> probe() async {
    if (!_active || _closed) return;
    final generation = ++_generation;
    _probe?.cancel();
    final cancellation = _probe = Cancellation();
    var status = Reachability.unreachable;
    try {
      final response = await transport.open(
        uri,
        method: 'HEAD',
        cancellation: cancellation,
      );
      await response.body.drain<void>();
      if (response.status >= 200 && response.status < 300) {
        status = Reachability.reachable;
      }
    } catch (_) {
      /* Reachability is reported separately from business errors. */
    }
    if (!_active || _closed || generation != _generation) return;
    onChanged(status);
    _timer?.cancel();
    _timer = Timer(interval, () => unawaited(probe()));
  }

  void close() {
    _closed = true;
    _active = false;
    _generation++;
    _timer?.cancel();
    _probe?.cancel();
  }
}
