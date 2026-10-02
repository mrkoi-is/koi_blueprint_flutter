import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/app.dart';
import 'package:network_lab/bootstrap.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';

void main() {
  test(
    'bootstrap validates URL and closes transport after store startup failure',
    () async {
      await expectLater(
        NetworkBootstrap.create(baseUri: Uri.parse('file:///bad')),
        throwsArgumentError,
      );
      final transport = FakeTransport(
        (u, m, h, c) => throw StateError('unused'),
      );
      await expectLater(
        NetworkBootstrap.create(
          baseUri: Uri.parse('http://fixture/'),
          transportFactory: () => transport,
          storeFactory: () async => throw StateError('store failed'),
        ),
        throwsStateError,
      );
      expect(transport.closed, true);
    },
  );
  testWidgets(
    'real router search, refresh, terminal transfer and lifecycle close',
    (tester) async {
      var fail = false;
      final transport = FakeTransport((uri, method, headers, cancellation) {
        if (uri.path == '/health') {
          return HttpPayload(
            status: 204,
            headers: {},
            body: const Stream.empty(),
          );
        }
        if (uri.path == '/catalog') {
          return HttpPayload(
            status: fail ? 503 : 200,
            headers: {},
            body: Stream.value(
              utf8.encode(
                jsonEncode({
                  'items': [
                    {'id': 'a', 'label': 'Fixture result'},
                  ],
                  'nextCursor': null,
                }),
              ),
            ),
          );
        }
        return HttpPayload(
          status: 200,
          headers: {'content-length': '3'},
          body: method == 'HEAD'
              ? const Stream.empty()
              : Stream.value([1, 2, 3]),
        );
      });
      final store = MemoryTransferStore();
      final boot = await NetworkBootstrap.create(
        baseUri: Uri.parse('http://fixture/'),
        transportFactory: () => transport,
        storeFactory: () async => store,
      );
      await tester.pumpWidget(
        NetworkLabApp(bootstrap: boot, locale: const Locale('zh')),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络实验室'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();
      expect(find.text('Fixture result'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '加载更多'))
            .onPressed,
        isNull,
      );
      fail = true;
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('503'), findsOneWidget);
      expect(find.text('Fixture result'), findsOneWidget);
      await tester.tap(find.text('清理查询缓存'));
      await tester.tap(find.text('下载 / 重试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('传输：已完成'), findsOneWidget);
      expect(find.textContaining('SHA256:'), findsOneWidget);
      expect(store.completed['fixture_download'], [1, 2, 3]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await boot.close();
      expect(store.closed, true);
      expect(transport.closed, true);
    },
  );
}
