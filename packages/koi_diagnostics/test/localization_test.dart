import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_diagnostics/koi_diagnostics.dart';
import 'package:koi_diagnostics/src/diagnostic_lan_native.dart' as native;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'failed foreground stop retains ownership so cleanup can be retried',
    () async {
      const channel = MethodChannel('flutter_foreground_task/methods');
      const hostChannel = MethodChannel('koi/diagnostics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var serviceRunning = false;
      var stopCalls = 0;
      messenger.setMockMethodCallHandler(hostChannel, (_) async => null);
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isRunningService':
            return serviceRunning;
          case 'requestNotificationPermission':
            return NotificationPermission.granted.index;
          case 'isIgnoringBatteryOptimizations':
            return true;
          case 'startService':
            serviceRunning = true;
          case 'stopService':
            if (++stopCalls == 1) throw PlatformException(code: 'stop_failed');
            serviceRunning = false;
        }
        return null;
      });
      final store = BoundedDiagnosticStore();
      final lan = native.DiagnosticLan(() => store, isAndroid: true);
      try {
        await lan.start(address: '127.0.0.1');
        await lan.stop();
        expect(lan.error, isNotNull);
        expect(serviceRunning, isTrue);
        await lan.stop();
        expect(stopCalls, 2);
        expect(serviceRunning, isFalse);
      } finally {
        await lan.close();
        await store.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(hostChannel, null);
      }
    },
  );

  test(
    'concurrent stops share cleanup and prevent restart until it finishes',
    () async {
      const channel = MethodChannel('flutter_foreground_task/methods');
      const hostChannel = MethodChannel('koi/diagnostics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final stopping = Completer<void>();
      final releaseStop = Completer<void>();
      var serviceRunning = false;
      var stopCalls = 0;
      messenger.setMockMethodCallHandler(hostChannel, (_) async => null);
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isRunningService':
            return serviceRunning;
          case 'requestNotificationPermission':
            return NotificationPermission.granted.index;
          case 'isIgnoringBatteryOptimizations':
            return true;
          case 'startService':
            serviceRunning = true;
          case 'stopService':
            stopCalls++;
            if (!stopping.isCompleted) stopping.complete();
            await releaseStop.future;
            serviceRunning = false;
        }
        return null;
      });
      final store = BoundedDiagnosticStore();
      final lan = native.DiagnosticLan(() => store, isAndroid: true);
      Future<void>? firstStop;
      try {
        await lan.start(address: '127.0.0.1');
        expect(lan.running, isTrue);
        firstStop = lan.stop();
        await stopping.future.timeout(const Duration(seconds: 5));
        expect(lan.busy, isTrue);
        final secondStop = lan.stop();
        await lan
            .start(address: '127.0.0.1')
            .timeout(const Duration(seconds: 5));
        expect(lan.running, isFalse);
        expect(stopCalls, 1);
        releaseStop.complete();
        await Future.wait([firstStop, secondStop])
            .timeout(const Duration(seconds: 5));
        expect(lan.busy, isFalse);
        expect(serviceRunning, isFalse);
        await lan.start(address: '127.0.0.1');
        expect(lan.running, isTrue);
      } finally {
        if (!releaseStop.isCompleted) releaseStop.complete();
        await firstStop;
        await lan.close();
        await store.close();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(hostChannel, null);
      }
    },
  );

  for (final (language, tag, title, notice, body, failure) in [
    (
      'en',
      'en',
      'Diagnostics',
      'LAN diagnostics',
      'LAN viewer is running',
      'Export failed (HTTP {status}).',
    ),
    ('zh', 'zh-Hans', '诊断', '局域网诊断', '局域网查看服务正在运行', '导出失败（HTTP {status}）。'),
    (
      'zh_Hant',
      'zh-Hant',
      '診斷',
      '區域網路診斷',
      '區域網路檢視服務執行中',
      '匯出失敗（HTTP {status}）。',
    ),
  ]) {
    test(
      '$language reaches the LAN document and Android notification',
      () async {
        const channel = MethodChannel('flutter_foreground_task/methods');
        const hostChannel = MethodChannel('koi/diagnostics');
        final calls = <MethodCall>[];
        var serviceRunning = false;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(hostChannel, (call) async {
          expect(call.method, 'localizeNotificationChannel');
          expect(call.arguments, {'name': notice});
          calls.add(call);
          return null;
        });
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isRunningService':
              return serviceRunning;
            case 'requestNotificationPermission':
              return NotificationPermission.granted.index;
            case 'isIgnoringBatteryOptimizations':
              return true;
            case 'startService':
              serviceRunning = true;
            case 'stopService':
              serviceRunning = false;
          }
          return null;
        });
        final store = BoundedDiagnosticStore();
        final lan = native.DiagnosticLan(() => store, isAndroid: true);
        final client = HttpClient();
        try {
          await lan.start(address: '127.0.0.1', language: language);
          expect(lan.error, isNull);
          expect(lan.running, isTrue);
          final start = calls.singleWhere(
            (call) => call.method == 'startService',
          );
          final args = start.arguments as Map;
          expect(args['notificationContentTitle'], notice);
          expect(args['notificationContentText'], body);
          expect(
            FlutterForegroundTask.androidNotificationOptions!.channelName,
            notice,
          );
          final request = await client.getUrl(Uri.parse(lan.address!));
          final html = await utf8.decodeStream(await request.close());
          expect(html, contains('<html lang="$tag">'));
          expect(html, contains('<title>$title</title>'));
          final vocabulary = jsonDecode(
            RegExp(r'const words=(.*);').firstMatch(html)![1]!,
          ) as Map;
          expect(vocabulary['exportFailure'], failure);
        } finally {
          client.close(force: true);
          await lan.close();
          await store.close();
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(hostChannel, null);
        }
        expect(serviceRunning, isFalse);
      },
    );
  }

  test('language tags accept script and region preferences without mislabeling HTML', () {
    for (final tag in [
      'zh-Hant',
      'ZH_hant',
      'zh-TW',
      'zh-HK',
      'zh-MO',
      'zh-Hant-CN',
    ]) {
      expect(DiagnosticStrings(tag).languageTag, 'zh-Hant');
      expect(DiagnosticStrings(tag).title, '診斷');
    }
    for (final tag in ['zh', 'zh-CN', 'zh-Hans-TW']) {
      expect(DiagnosticStrings(tag).languageTag, 'zh-Hans');
      expect(DiagnosticStrings(tag).title, '诊断');
    }
    expect(const DiagnosticStrings('fr').languageTag, 'en');
    expect(const DiagnosticStrings('fr').title, 'Diagnostics');
  });
}
