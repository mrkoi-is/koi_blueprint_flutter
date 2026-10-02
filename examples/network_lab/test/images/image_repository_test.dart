import 'dart:async';
import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/images/data/image_repository.dart';
import 'package:network_lab/features/images/data/image_validator.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

import '../support/fakes.dart';
import 'image_fixtures.dart';

class Reader implements LocalImageReader {
  Reader(this.bytes);
  final Uint8List bytes;
  bool closed = false;
  @override
  Future<Uint8List> read(String key, {required int maxBytes}) async => bytes;
  @override
  Future<String?> pick({required int maxBytes}) async => 'local';
  @override
  void close() {
    closed = true;
  }
}

Future<Uint8List> sample() async => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEUlEQVR4nGNgSDkBQidSQAgAIN4EsaJdpP4AAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('typed asset/memory/local sources use actual decoder and reject corrupt/budget-exceeding bytes', () async {
    final bytes = await sample();
    final reader = Reader(bytes);
    final repo = ImageRepositoryImpl(
      transport: FakeTransport((u, m, h, c) => throw StateError('no network')),
      localReader: reader,
      assetReader: (_) async => bytes,
      validator: const FlutterImageValidator(),
    );
    for (final source in [
      const AssetImageSource('sample'),
      MemoryImageSource(bytes),
      const LocalImageSource('local'),
    ]) {
      expect(
        (await repo.load(source, cancellation: Cancellation())).bytes,
        bytes,
      );
    }
    final memory = MemoryImageSource(bytes);
    memory.bytes[0] = 0;
    expect(memory.bytes[0], 137);
    await expectLater(
      repo.load(MemoryImageSource([1, 2]), cancellation: Cancellation()),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      const FlutterImageValidator(maxPixels: 1).validate(bytes),
      throwsStateError,
    );
    await repo.close();
    expect(reader.closed, true);
    await expectLater(
      repo.load(memory, cancellation: Cancellation()),
      throwsStateError,
    );
  });
  test('validated network cache serves offline within TTL, never caches 403/404/decode errors and retries', () async {
    final bytes = await sample();
    var now = DateTime.utc(2026);
    var status = 200;
    var corrupt = false;
    final transport = FakeTransport(
      (u, m, h, c) => HttpPayload(
        status: status,
        headers: {},
        body: Stream.value(corrupt ? [1, 2] : bytes),
      ),
    );
    final repo = ImageRepositoryImpl(
      transport: transport,
      localReader: Reader(bytes),
      assetReader: (_) async => bytes,
      validator: const FlutterImageValidator(),
      now: () => now,
      ttl: const Duration(seconds: 1),
    );
    final source = NetworkImageSource(Uri.parse('http://fixture/image'));
    expect(
      (await repo.load(source, cancellation: Cancellation())).fromCache,
      false,
    );
    status = 403;
    expect(
      (await repo.load(source, cancellation: Cancellation())).fromCache,
      true,
    );
    expect(transport.requests, 1);
    now = now.add(const Duration(seconds: 1));
    for (status in [403, 404]) {
      await expectLater(
        repo.load(source, cancellation: Cancellation()),
        throwsA(predicate((error) => error.toString().contains('$status'))),
      );
    }
    status = 200;
    corrupt = true;
    await expectLater(
      repo.load(source, cancellation: Cancellation()),
      throwsA(isA<Exception>()),
    );
    corrupt = false;
    expect(
      (await repo.load(source, cancellation: Cancellation())).fromCache,
      false,
    );
    repo.clear();
    expect(
      (await repo.load(source, cancellation: Cancellation())).fromCache,
      false,
    );
    await repo.close();
  });
  test('concurrent loads share one request; cancelling one reader preserves the other', () async {
    final bytes = await sample();
    final pending = Completer<HttpPayload>();
    late Cancellation wire;
    final transport = FakeTransport((u, m, h, c) {
      wire = c;
      return pending.future;
    });
    final repo = ImageRepositoryImpl(
      transport: transport,
      localReader: Reader(bytes),
      assetReader: (_) async => bytes,
      validator: const FlutterImageValidator(),
    );
    final source = NetworkImageSource(Uri.parse('http://fixture/image'));
    final firstCancel = Cancellation();
    final first = repo.load(source, cancellation: firstCancel);
    final second = repo.load(source, cancellation: Cancellation());
    final rejected = expectLater(first, throwsA(isA<RequestCancelled>()));
    firstCancel.cancel();
    await rejected;
    expect(wire.isCancelled, false);
    expect(transport.requests, 1);
    pending.complete(
      HttpPayload(status: 200, headers: {}, body: Stream.value(bytes)),
    );
    expect((await second).bytes, bytes);
    await repo.close();
  });
  test(
    'JPEG GIF and WebP headers and actual codecs agree; malformed headers fail',
    () async {
      for (final entry in imageFixtures.entries) {
        final bytes = base64Decode(entry.value);
        expect(imageDimensions(bytes), (
          width: 2,
          height: 2,
        ), reason: entry.key);
        await const FlutterImageValidator().validate(bytes);
      }
      expect(
        () => imageDimensions(Uint8List.fromList([255, 216, 255, 192, 0, 1])),
        throwsFormatException,
      );
      expect(
        () => imageDimensions(Uint8List.fromList([0, 1, 2])),
        throwsFormatException,
      );
    },
  );
  test(
    'last reader cancellation aborts transport and does not publish cache',
    () async {
      final bytes = await sample();
      var cancelled = false;
      final transport = FakeTransport((u, m, h, c) async {
        final done = Completer<void>();
        c.onCancel(() {
          cancelled = true;
          done.complete();
        });
        await done.future;
        c.check();
        throw StateError('unreachable');
      });
      final repo = ImageRepositoryImpl(
        transport: transport,
        localReader: Reader(bytes),
        assetReader: (_) async => bytes,
        validator: const FlutterImageValidator(),
      );
      final token = Cancellation();
      final pending = repo.load(
        NetworkImageSource(Uri.parse('http://fixture/image')),
        cancellation: token,
      );
      final failure = expectLater(pending, throwsA(isA<RequestCancelled>()));
      token.cancel();
      await failure;
      expect(cancelled, true);
      await repo.close();
    },
  );
}
