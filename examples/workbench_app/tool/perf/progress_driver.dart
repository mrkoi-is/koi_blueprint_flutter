import 'dart:async';

/// A finite, bounded test driver. Deadline mode schedules against elapsed wall
/// time, independently of consumer pauses. Delayed emissions are reported as
/// bursts and lateness, rather than presented as uniformly spaced events.
final class ProgressDriver {
  ProgressDriver({
    required this.mode,
    this.chunks = 1000,
    this.period = const Duration(milliseconds: 5),
    this.chunkBytes = 128,
    this.lineBreaks = false,
  }) {
    if (!['legacy', 'deadline'].contains(mode)) {
      throw ArgumentError.value(mode, 'mode');
    }
  }

  final String mode;
  final int chunks;
  final Duration period;
  final int chunkBytes;
  final bool lineBreaks;
  final clock = Stopwatch();
  final emittedAtUs = <int>[];
  final deliveredAtUs = <int>[];
  int maxBurst = 0;
  int maxQueued = 0;
  bool _opened = false;

  List<int> _chunk() {
    final bytes = List.filled(chunkBytes, 120);
    if (lineBreaks) bytes[chunkBytes - 1] = 10;
    return bytes;
  }

  Stream<List<int>> open() {
    if (_opened) throw StateError('Each measurement requires a fresh driver');
    _opened = true;
    final stream = mode == 'legacy' ? _legacy() : _deadline();
    return stream.map((chunk) {
      deliveredAtUs.add(clock.elapsedMicroseconds);
      return chunk;
    });
  }

  Stream<List<int>> _legacy() async* {
    clock.start();
    await for (final _ in Stream<void>.periodic(period).take(chunks)) {
      emittedAtUs.add(clock.elapsedMicroseconds);
      maxBurst = 1;
      yield _chunk();
    }
  }

  Stream<List<int>> _deadline() {
    late final StreamController<List<int>> controller;
    Timer? timer;
    var cancelled = false;
    void tick() {
      if (cancelled) return;
      final due = (clock.elapsedMicroseconds ~/ period.inMicroseconds).clamp(
        0,
        chunks,
      );
      final burst = due - emittedAtUs.length;
      if (burst > maxBurst) maxBurst = burst;
      while (emittedAtUs.length < due) {
        emittedAtUs.add(clock.elapsedMicroseconds);
        controller.add(_chunk());
      }
      final queued = emittedAtUs.length - deliveredAtUs.length;
      if (queued > maxQueued) maxQueued = queued;
      if (emittedAtUs.length == chunks) {
        unawaited(controller.close());
      } else {
        final remaining =
            (emittedAtUs.length + 1) * period.inMicroseconds -
            clock.elapsedMicroseconds;
        timer = Timer(
          Duration(microseconds: remaining.clamp(0, 1 << 31)),
          tick,
        );
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        clock.start();
        timer = Timer(period, tick);
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  Map<String, Object?> get metrics => {
    'mode': mode,
    'requestedHz': 1000000 / period.inMicroseconds,
    'emitted': emittedAtUs.length,
    'delivered': deliveredAtUs.length,
    'producerElapsedMs': emittedAtUs.lastOrNull == null
        ? 0
        : emittedAtUs.last / 1000,
    'deliveryElapsedMs': deliveredAtUs.lastOrNull == null
        ? 0
        : deliveredAtUs.last / 1000,
    'achievedProducerHz': emittedAtUs.isEmpty
        ? 0
        : emittedAtUs.length * 1000000 / emittedAtUs.last,
    'achievedDeliveryHz': deliveredAtUs.isEmpty
        ? 0
        : deliveredAtUs.length * 1000000 / deliveredAtUs.last,
    'maxBurst': maxBurst,
    'maxQueuedChunks': maxQueued,
    'emissionIntervalMs': distribution([
      for (var i = 1; i < emittedAtUs.length; i++)
        (emittedAtUs[i] - emittedAtUs[i - 1]) / 1000,
    ]),
    'deadlineLatenessMs': distribution([
      for (var i = 0; i < emittedAtUs.length; i++)
        (emittedAtUs[i] - (i + 1) * period.inMicroseconds) / 1000,
    ]),
    'queuedDeliveryMs': distribution([
      for (var i = 0; i < deliveredAtUs.length; i++)
        (deliveredAtUs[i] - emittedAtUs[i]) / 1000,
    ]),
  };
}

Map<String, Object?> distribution(List<double> values) {
  if (values.isEmpty) return {'samples': 0};
  values.sort();
  return {
    'samples': values.length,
    'p50': values[values.length ~/ 2],
    'p95': values[((values.length - 1) * .95).floor()],
    'max': values.last,
  };
}
