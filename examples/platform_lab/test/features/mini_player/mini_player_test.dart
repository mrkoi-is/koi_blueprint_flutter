import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/mini_player/presentation/mini_player_page.dart';
import 'package:platform_lab/features/desktop_window/application/window_host.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/presentation/providers/system_media_providers.dart';

import '../desktop_window/support.dart';
import '../system_media/support.dart';

void main() {
  testWidgets(
    'mini view preserves player identity and restores window on navigation removal',
    (tester) async {
      final window = FakeWindow();
      final host = DesktopWindowHost(
        port: window,
        store: FakeGeometryStore(),
        requestExit: () async => true,
      );
      final engine = FakeMediaEngine();
      final media = MediaSessionController(engine);
      await host.initialize();
      await media.open('test://one', 'One');
      await media.play();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopWindowHostProvider.overrideWithValue(host),
            systemMediaControllerProvider.overrideWithValue(media),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              KoiUiLocalizations.delegate,
              ...AppLocalizations.localizationsDelegates,
            ],
            theme: AppTheme.light,
            home: const MiniPlayerPage(),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Enter mini mode'));
      await tester.pumpAndSettle();
      expect(host.mini, isTrue);
      expect(engine.playing, isTrue);
      expect(engine.opens, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(host.mini, isFalse);
      expect(window.onTop, isFalse);
      await host.shutdown();
      await media.close();
    },
  );
}
