import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/desktop_window/application/window_host.dart';
import 'package:platform_lab/features/desktop_window/domain/window_geometry.dart';
import 'package:platform_lab/features/desktop_window/presentation/desktop_window_page.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';

import 'support.dart';

void main() {
  test('geometry rejects malformed values and recovers unplugged monitors', () {
    expect(
      WindowGeometry.fromJson({
        'x': 0,
        'y': 0,
        'width': double.nan,
        'height': 700,
      }),
      isNull,
    );
    expect(
      WindowGeometry.fromJson({'x': 0, 'y': 0, 'width': -1, 'height': 700}),
      isNull,
    );
    final value = WindowGeometry.fromJson({
      'x': 5000,
      'y': -300,
      'width': 2000,
      'height': 1500,
      'maximized': true,
    })!;
    final fit = value.fitTo([
      const WindowBounds.fromLTWH(-1440, 20, 1440, 880),
    ]);
    expect(fit.bounds.left, -1440);
    expect(fit.bounds.top, 20);
    expect(fit.bounds.width, 1440);
    expect(fit.bounds.height, 880);
    expect(fit.maximized, isTrue);
    expect(WindowGeometry.fromJson(fit.toJson())!.toJson(), fit.toJson());
  });
  test(
    'close hides only with a working tray; quit always requests guarded exit',
    () async {
      final port = FakeWindow();
      final store = FakeGeometryStore();
      var exits = 0;
      var allowExit = true;
      final host = DesktopWindowHost(
        port: port,
        store: store,
        requestExit: () async {
          exits++;
          return allowExit;
        },
      );
      await host.initialize();
      host.configureTray(available: false, closeToTray: true);
      await host.closeRequested();
      expect(exits, 1);
      expect(port.hidden, isFalse);
      host.configureTray(available: true, closeToTray: true);
      await host.closeRequested();
      expect(exits, 1);
      expect(port.hidden, isTrue);
      await host.show();
      expect(port.hidden, isFalse);
      await host.quit();
      expect(exits, 2);
      await port.hide();
      allowExit = false;
      await host.quit();
      expect(port.hidden, isFalse);
      expect(port.closed, isFalse);
      await host.shutdown();
      expect(port.closed, isTrue);
    },
  );
  test('mini transitions restore geometry and topmost after failure and rapid toggle', () async {
    final port = FakeWindow();
    final store = FakeGeometryStore();
    final host = DesktopWindowHost(
      port: port,
      store: store,
      requestExit: () async => true,
    );
    await host.initialize();
    final original = port.current.toJson();
    await host.setMini(true);
    expect(host.mini, isTrue);
    expect(port.onTop, isTrue);
    await host.saveGeometry();
    expect(store.value, isNull);
    await host.setMini(false);
    expect(port.current.toJson(), original);
    expect(port.onTop, isFalse);
    port.failMini = true;
    await host.setMini(true);
    expect(host.mini, isFalse);
    expect(host.error, contains('refused'));
    expect(port.current.toJson(), original);
    port.failMini = false;
    await Future.wait([host.setMini(true), host.setMini(false)]);
    expect(port.current.toJson(), original);
    expect(host.mini, isFalse);
    await host.shutdown();
  });
  test('failed geometry persistence remains retryable', () async {
    final store = FakeGeometryStore()..fail = true;
    final host = DesktopWindowHost(
      port: FakeWindow(),
      store: store,
      requestExit: () async => true,
    );
    await host.initialize();
    await host.saveGeometry();
    expect(host.error, contains('disk full'));
    store.fail = false;
    await host.saveGeometry();
    expect(host.error, isNull);
    await host.shutdown();
  });
  testWidgets(
    'desktop controls show the same resource and require tray readiness',
    (tester) async {
      final host = DesktopWindowHost(
        port: FakeWindow(),
        store: FakeGeometryStore(),
        requestExit: () async => true,
      );
      await host.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [desktopWindowHostProvider.overrideWithValue(host)],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              KoiUiLocalizations.delegate,
              ...AppLocalizations.localizationsDelegates,
            ],
            theme: AppTheme.light,
            home: const DesktopWindowPage(),
          ),
        ),
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      host.configureTray(available: true, closeToTray: false);
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(host.hideOnClose, isTrue);
      await tester.pumpWidget(const SizedBox());
      await host.shutdown();
    },
  );
}
