import 'dart:convert';
import 'dart:io';

import 'package:device_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

Future<void> waitForCapability(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), true, reason: 'Capability IO or stream must settle');
}

Future<T> completeCapability<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  var completed = false;
  T? value;
  Object? failure;
  StackTrace? trace;
  action().then(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      trace = stack;
      completed = true;
    },
  );
  await waitForCapability(tester, () => completed);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return value as T;
}

Widget capabilityHost(WidgetBuilder builder) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Builder(builder: builder),
);

class NativeCapabilityFixture {
  NativeCapabilityFixture(this.root);
  final Directory root;
  bool deny = false;
  int requests = 0;
  static const channel = MethodChannel('plugins.flutter.io/path_provider');

  static Future<NativeCapabilityFixture> create(WidgetTester tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('device-owner-'),
    ))!;
    final fixture = NativeCapabilityFixture(root);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      fixture.requests++;
      if (fixture.deny) {
        throw PlatformException(
          code: 'denied',
          message: 'fixture directory denied',
        );
      }
      return root.path;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await tester.pumpWidget(const SizedBox());
      await completeCapability(tester, CapabilityLifecycle.instance.close);
      await tester.runAsync(() => root.delete(recursive: true));
    });
    return fixture;
  }

  Future<Map<String, Object?>> read(
    WidgetTester tester,
    String namespace,
  ) async => (await tester.runAsync(
    () async => Map<String, Object?>.from(
      jsonDecode(
        await File('${root.path}/$namespace/settings.json').readAsString(),
      ) as Map,
    ),
  ))!;
}
