import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:network_lab/features/network/network_capability.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/data/search_repository.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';
import '../support/fixture_transport.dart';
import '../presentation/network_capability_test.dart' show pumpNetworkFrames;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('NETWORK_FIXTURE_URL');
  const digest = String.fromEnvironment('NETWORK_FIXTURE_SHA256');
  group(
    'owned real HTTP fixture',
    () {
      late HttpTransport transport;
      late Uri base;
      setUp(() {
        transport = createFixtureHttpTransport();
        base = Uri.parse(endpoint);
      });
      tearDown(() => transport.close());
      Future<Map<String, dynamic>> metrics({bool resetPeak = false}) async {
        final response = await transport.open(
          base.resolve(resetPeak ? 'metrics?resetPeak=true' : 'metrics'),
          cancellation: Cancellation(),
        );
        return jsonDecode(
          utf8.decode(await response.body.expand((v) => v).toList()),
        ) as Map<String, dynamic>;
      }

      testWidgets(
        'empty endpoint can be entered in the page and query the owned local HTTP fixture',
        (tester) async {
          final store = MemoryTransferStore();
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: NetworkCapabilityPage(
                endpoint: '',
                transportFactory: createFixtureHttpTransport,
                storeFactory: () async => store,
              ),
            ),
          );
          await pumpNetworkFrames(tester);
          expect(find.textContaining('NETWORK_LAB_URL'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('network-endpoint')),
            endpoint,
          );
          await tester.tap(find.byKey(const ValueKey('network-connect')));
          await pumpNetworkFrames(tester);
          await tester.runAsync(() async {
            await tester.enterText(find.byType(TextField), 'tea');
            await Future<void>.delayed(const Duration(milliseconds: 350));
          });
          for (
            var attempt = 0;
            attempt < 30 && find.text('tea item 0').evaluate().isEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
          }
          expect(
            find.text('tea item 0'),
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data)
                .join('\n'),
          );
          await tester.tap(find.byTooltip('Change service'));
          await pumpNetworkFrames(tester);
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('network-endpoint')),
                )
                .controller!
                .text,
            endpoint,
          );
          await tester.tap(find.text('Keep current service'));
          await pumpNetworkFrames(tester);
          expect(find.text('tea item 0'), findsOneWidget);
          expect(find.text('tea'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          await pumpNetworkFrames(tester);
          expect(store.closed, true);
        },
      );
      test('search pages use actual HTTP and failed requests never become cached success', () async {
        final repository = HttpSearchRepository(transport, base);
        final first = await repository.search(
          'tea',
          cancellation: Cancellation(),
        );
        expect(first.items, hasLength(5));
        expect(first.nextCursor, '5');
        final next = await repository.search(
          'tea',
          cursor: first.nextCursor,
          cancellation: Cancellation(),
        );
        expect(next.items.first.id, '5');
        await expectLater(
          repository.search('forbidden', cancellation: Cancellation()),
          throwsStateError,
        );
      });
      test('real ranged and ordinary transfers match SHA256', () async {
        await metrics(resetPeak: true);
        for (final path in ['file', 'file?mode=plain']) {
          final store = MemoryTransferStore();
          final states = <TransferSnapshot>[];
          final actual = await TransferEngine(transport, store).download(
            base.resolve(path),
            id: 'x',
            cancellation: Cancellation(),
            progress: states.add,
            expectedSha256: digest,
          );
          expect(actual, digest);
          expect(store.completed['x'], hasLength(2 * 1024 * 1024));
          expect(states.last.phase, TransferPhase.complete);
        }
        final server = await metrics();
        // The server observes overlapping real requests. The exact upper bound
        // (including completed buffers waiting for storage) is tested with a
        // controlled transport; server handlers can briefly outlive their EOF.
        expect(server['peakActive'], greaterThanOrEqualTo(2));
      });
      test('cancellation aborts server response and discards staging before settling', () async {
        final before = await metrics();
        final store = MemoryTransferStore();
        final cancellation = Cancellation();
        await expectLater(
          TransferEngine(transport, store).download(
            base.resolve('file'),
            id: 'x',
            cancellation: cancellation,
            progress: (state) {
              if (state.received >= 8192) cancellation.cancel();
            },
          ),
          throwsA(isA<RequestCancelled>()),
        );
        expect(store.stages, isEmpty);
        expect(store.completed, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final after = await metrics();
        expect(after['aborted'] as int, greaterThan(before['aborted'] as int));
      });
      test(
        'changed ETag and malformed range cannot publish a completed artifact',
        () async {
          for (final mode in ['changed', 'wrong', 'short']) {
            final store = MemoryTransferStore();
            await expectLater(
              TransferEngine(transport, store).download(
                base.resolve('file?mode=$mode'),
                id: 'x',
                cancellation: Cancellation(),
                progress: (_) {},
              ),
              throwsA(anything),
            );
            expect(store.completed, isEmpty);
          }
        },
      );
    },
    skip: endpoint.isEmpty
        ? 'Run tool/run_http_smoke.py for owned HTTP evidence'
        : false,
  );
}
