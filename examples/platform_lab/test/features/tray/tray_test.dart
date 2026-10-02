import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/tray/presentation/tray_page.dart';
import 'package:platform_lab/features/tray/presentation/providers/tray_providers.dart';
import 'package:platform_lab/features/tray/data/tray_port.dart';
import 'package:platform_lab/features/desktop_window/application/window_host.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';

import '../desktop_window/support.dart';

class FakeTray implements TrayPort {
  @override
  Future<bool> open({
    required void Function() show,
    required void Function() quit,
    String showLabel = 'Show window',
    String quitLabel = 'Quit',
  }) async => true;
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('tray UI cannot hide a window until a tray is available', (
    tester,
  ) async {
    final host = DesktopWindowHost(
      port: FakeWindow(),
      store: FakeGeometryStore(),
      requestExit: () async => true,
    );
    await host.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopWindowHostProvider.overrideWithValue(host),
          trayPortProvider.overrideWithValue(FakeTray()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            KoiUiLocalizations.delegate,
            ...AppLocalizations.localizationsDelegates,
          ],
          theme: AppTheme.light,
          home: const TrayPage(),
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
  });
}
