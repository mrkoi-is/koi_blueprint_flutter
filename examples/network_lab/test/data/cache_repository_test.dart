import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/data/response_cache.dart';
import 'package:network_lab/features/network/data/search_repository.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';

void main() {
  test('default cache retains success for five minutes with at most 128 LRU entries', () {
    var now = DateTime.utc(2026);
    final cache = ResponseCache(now: () => now);
    cache.put('oldest', [1]);
    for (var index = 0; index < 127; index++) {
      cache.put('q$index', [index]);
    }
    expect(cache.count, 128);
    cache.get('oldest');
    cache.put('newest', [2]);
    expect(cache.count, 128);
    expect(cache.get('q0'), isNull);
    now = now.add(const Duration(minutes: 5) - const Duration(milliseconds: 1));
    expect(cache.get('oldest'), [1]);
    now = now.add(const Duration(milliseconds: 1));
    expect(cache.get('oldest'), isNull);
    expect(cache.get('newest'), isNull);
  });
  test(
    'cache expiry is exact, LRU bounded, copies independent and clear scoped',
    () {
      var now = DateTime.utc(2026);
      final cache = ResponseCache(
        maxBytes: 4,
        maxEntries: 2,
        ttl: const Duration(seconds: 1),
        now: () => now,
      );
      cache.put('a', [1, 2]);
      cache.put('b', [3]);
      cache.get('a')![0] = 99;
      expect(cache.get('a'), [1, 2]);
      cache.put('c', [4, 5]);
      expect(cache.get('b'), isNull);
      expect(cache.sizeBytes, 4);
      cache.put('too-large', [1, 2, 3, 4, 5]);
      expect(cache.count, 2);
      now = now.add(const Duration(seconds: 1));
      expect(cache.get('a'), isNull);
      cache.clear();
      expect(cache.sizeBytes, 0);
      expect(() => ResponseCache(maxBytes: 0), throwsArgumentError);
    },
  );
  test(
    'search caches only valid success and scopes source/version/session',
    () async {
      var status = 200;
      var malformed = false;
      final transport = FakeTransport(
        (uri, method, headers, cancel) => HttpPayload(
          status: status,
          headers: {},
          body: Stream.value(
            utf8.encode(
              malformed
                  ? '{}'
                  : jsonEncode({
                      'items': [
                        {'id': 'a', 'label': uri.queryParameters['q']},
                      ],
                      'nextCursor': null,
                      'total': 1,
                    }),
            ),
          ),
        ),
      );
      final cache = ResponseCache();
      final repository = HttpSearchRepository(
        transport,
        Uri.parse('http://fixture/'),
        cache: cache,
      );
      Future<void> search({bool refresh = false}) async {
        await repository.search(
          ' tea ',
          cancellation: Cancellation(),
          refresh: refresh,
        );
      }

      expect(
        (await repository.search('', cancellation: Cancellation())).items,
        isEmpty,
      );
      expect(transport.requests, 0);
      await search();
      await search();
      expect(transport.requests, 1);
      await HttpSearchRepository(
        transport,
        Uri.parse('http://fixture/'),
        cache: cache,
        scope: 'another-account',
      ).search('tea', cancellation: Cancellation());
      expect(transport.requests, 2);
      status = 403;
      await expectLater(search(refresh: true), throwsStateError);
      expect(transport.requests, 3);
      repository.clear();
      await expectLater(search(), throwsStateError);
      expect(cache.count, 0);
      status = 200;
      malformed = true;
      await expectLater(search(), throwsA(anything));
      expect(cache.count, 0);
    },
  );
  test('cancellation detaches and transport never sees empty queries', () {
    final signal = Cancellation();
    var count = 0;
    final detach = signal.onCancel(() => count++);
    detach();
    signal.onCancel(() => count++);
    signal.cancel();
    signal.cancel();
    signal.onCancel(() => count++);
    expect(count, 2);
    expect(signal.check, throwsA(isA<RequestCancelled>()));
  });
}
