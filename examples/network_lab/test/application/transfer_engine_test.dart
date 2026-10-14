import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';

void main() {
  test('parallel range window stays bounded and commits out-of-order responses in order', () async {
    final source = List<int>.generate(32, (index) => index);
    final gates = {
      for (final start in [0, 4, 8]) start: Completer<void>(),
    };
    final started = <int>[];
    final completed = <int>[];
    var active = 0;
    var peak = 0;
    final transport = FakeTransport((uri, method, headers, cancellation) {
      if (method == 'HEAD') {
        return HttpPayload(
          status: 200,
          headers: {
            'content-length': '32',
            'etag': '"v1"',
            'accept-ranges': 'bytes',
          },
          body: const Stream.empty(),
        );
      }
      final range = headers['Range']!
          .substring(6)
          .split('-')
          .map(int.parse)
          .toList();
      final start = range[0], end = range[1];
      Stream<List<int>> body() async* {
        started.add(start);
        active++;
        if (active > peak) peak = active;
        try {
          await (gates[start]?.future ?? Future<void>.value());
          cancellation.check();
          yield source.sublist(start, end + 1);
          completed.add(start);
        } finally {
          active--;
        }
      }

      return HttpPayload(
        status: 206,
        headers: {'content-range': 'bytes $start-$end/32', 'etag': '"v1"'},
        body: body(),
      );
    });
    final store = MemoryTransferStore();
    final pending = TransferEngine(transport, store, rangeBytes: 4).download(
      Uri.parse('http://fixture/file'),
      id: 'parallel',
      cancellation: Cancellation(),
      progress: (_) {},
      expectedSha256: sha256.convert(source).toString(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 4, 8]);
    gates[8]!.complete();
    gates[4]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(completed, [8, 4]);
    expect(started, [0, 4, 8]); // Completed buffers still occupy their slots.
    expect(store.stages['parallel'], isEmpty);
    gates[0]!.complete();
    await pending;
    expect(peak, 3);
    expect(active, 0);
    expect(store.completed['parallel'], source);
  });

  test(
    'cancellation drains every concurrent reader before deleting staged bytes',
    () async {
      var active = 0;
      final ready = Completer<void>();
      final transport = FakeTransport((uri, method, headers, cancellation) {
        if (method == 'HEAD') {
          return HttpPayload(
            status: 200,
            headers: {
              'content-length': '12',
              'etag': '"v1"',
              'accept-ranges': 'bytes',
            },
            body: const Stream.empty(),
          );
        }
        final range = headers['Range']!.substring(6);
        Stream<List<int>> body() async* {
          active++;
          if (active == 3) ready.complete();
          final stopped = Completer<void>();
          final detach = cancellation.onCancel(() => stopped.complete());
          try {
            await stopped.future;
            cancellation.check();
          } finally {
            detach();
            active--;
          }
        }

        return HttpPayload(
          status: 206,
          headers: {'content-range': 'bytes $range/12', 'etag': '"v1"'},
          body: body(),
        );
      });
      final store = MemoryTransferStore();
      final cancel = Cancellation();
      final pending = TransferEngine(transport, store, rangeBytes: 4).download(
        Uri.parse('http://fixture/file'),
        id: 'cancel',
        cancellation: cancel,
        progress: (_) {},
      );
      final assertion = expectLater(pending, throwsA(isA<RequestCancelled>()));
      await ready.future;
      cancel.cancel();
      await assertion;
      expect(active, 0);
      expect(store.stages, isEmpty);
      expect(store.completed, isEmpty);
      expect(
        () => TransferEngine(transport, store, maxConcurrentRanges: 0),
        throwsArgumentError,
      );
      expect(
        () => TransferEngine(transport, store, maxConcurrentRanges: 9),
        throwsArgumentError,
      );
    },
  );
  final bytes = List<int>.generate(10, (index) => index);
  FakeTransport transportFor({
    bool range = true,
    String mode = 'ok',
    List<int>? starts,
  }) => FakeTransport((uri, method, headers, cancel) {
    final base = {
      'content-length': '10',
      'etag': '"v1"',
      'accept-ranges': range ? 'bytes' : 'none',
    };
    if (method == 'HEAD') {
      return HttpPayload(
        status: 200,
        headers: base,
        body: const Stream.empty(),
      );
    }
    if (!range) {
      return HttpPayload(
        status: 200,
        headers: base,
        body: Stream.fromIterable([bytes.sublist(0, 4), bytes.sublist(4)]),
      );
    }
    final interval = headers['Range']!
        .substring(6)
        .split('-')
        .map(int.parse)
        .toList();
    final start = interval[0], end = interval[1];
    starts?.add(start);
    final responseHeaders = {
      ...base,
      'content-range': 'bytes ${mode == 'wrong' ? start + 1 : start}-$end/10',
      'etag': mode == 'changed' ? '"v2"' : '"v1"',
    };
    return HttpPayload(
      status: 206,
      headers: responseHeaders,
      body: Stream.value(bytes.sublist(start, mode == 'short' ? end : end + 1)),
    );
  });
  test(
    'ranges are bounded, validate digest and commit only complete bytes',
    () async {
      final starts = <int>[];
      final store = MemoryTransferStore();
      final states = <TransferSnapshot>[];
      final engine = TransferEngine(
        transportFor(starts: starts),
        store,
        rangeBytes: 4,
      );
      final digest = await engine.download(
        Uri.parse('http://fixture/file'),
        id: 'x',
        cancellation: Cancellation(),
        progress: states.add,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(starts, [0, 4, 8]);
      expect(store.completed['x'], bytes);
      expect(store.stages, isEmpty);
      expect(digest, sha256.convert(bytes).toString());
      expect(states.last.phase, TransferPhase.complete);
    },
  );
  test('valid interrupted bytes resume only with matching source strong ETag and size', () async {
    final store = MemoryTransferStore();
    final uri = Uri.parse('http://fixture/file');
    await store.begin(
      'x',
      TransferMetadata(source: uri.toString(), etag: '"v1"', total: 10),
    );
    await store.append('x', bytes.sublist(0, 3));
    final starts = <int>[];
    await TransferEngine(
      transportFor(starts: starts),
      store,
      rangeBytes: 4,
    ).download(uri, id: 'x', cancellation: Cancellation(), progress: (_) {});
    expect(starts, [3, 7]);
    expect(store.completed['x'], bytes);
    await store.begin(
      'x',
      TransferMetadata(source: uri.toString(), etag: '"old"', total: 10),
    );
    await store.append('x', [99]);
    starts.clear();
    await TransferEngine(
      transportFor(starts: starts),
      store,
      rangeBytes: 4,
    ).download(uri, id: 'x', cancellation: Cancellation(), progress: (_) {});
    expect(starts.first, 0);
  });
  test('non-range response streams from zero and expected digest mismatch discards', () async {
    final store = MemoryTransferStore();
    final engine = TransferEngine(transportFor(range: false), store);
    await expectLater(
      engine.download(
        Uri.parse('http://fixture/file'),
        id: 'x',
        cancellation: Cancellation(),
        progress: (_) {},
        expectedSha256: 'wrong',
      ),
      throwsStateError,
    );
    expect(store.completed, isEmpty);
    expect(store.stages, isEmpty);
    await engine.download(
      Uri.parse('http://fixture/file'),
      id: 'x',
      cancellation: Cancellation(),
      progress: (_) {},
    );
    expect(store.completed['x'], bytes);
  });
  for (final mode in ['wrong', 'changed', 'short']) {
    test('rejects $mode range without publishing artifact', () async {
      final store = MemoryTransferStore();
      await expectLater(
        TransferEngine(transportFor(mode: mode), store, rangeBytes: 4).download(
          Uri.parse('http://fixture/file'),
          id: 'x',
          cancellation: Cancellation(),
          progress: (_) {},
        ),
        throwsStateError,
      );
      expect(store.completed, isEmpty);
    });
  }
  test(
    'cancellation stops stream and removes staging before completing',
    () async {
      final store = MemoryTransferStore();
      final cancellation = Cancellation();
      await expectLater(
        TransferEngine(transportFor(), store, rangeBytes: 4).download(
          Uri.parse('http://fixture/file'),
          id: 'x',
          cancellation: cancellation,
          progress: (state) {
            if (state.received >= 4) cancellation.cancel();
          },
        ),
        throwsA(isA<RequestCancelled>()),
      );
      expect(store.stages, isEmpty);
      expect(store.completed, isEmpty);
    },
  );
  test('quota rejects metadata before allocating stage', () async {
    final store = MemoryTransferStore();
    await expectLater(
      TransferEngine(transportFor(), store, maxBytes: 5).download(
        Uri.parse('http://fixture/file'),
        id: 'x',
        cancellation: Cancellation(),
        progress: (_) {},
      ),
      throwsStateError,
    );
    expect(store.stages, isEmpty);
  });
}
