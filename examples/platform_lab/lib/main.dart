import 'package:platform_lab/features/settings/presentation/settings_page.dart';
import 'package:platform_lab/features/settings/presentation/providers/settings_providers.dart';
import 'package:platform_lab/l10n/generated/app_localizations.dart';

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/desktop_window/presentation/desktop_window_page.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';
import 'package:platform_lab/features/tray/presentation/tray_page.dart';
import 'package:platform_lab/features/tray/presentation/providers/tray_providers.dart';
import 'package:platform_lab/features/system_media/presentation/system_media_page.dart';
import 'package:platform_lab/features/system_media/presentation/providers/system_media_providers.dart';
import 'package:platform_lab/features/mini_player/presentation/mini_player_page.dart';
import 'package:platform_lab/features/home_widget/presentation/home_widget_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSettingsPreferences();
  await initializeDesktopWindow();
  await initializeTray();
  await initializeSystemMedia();
  runApp(const ProviderScope(child: PlatformLab()));
}

class PlatformLab extends ConsumerStatefulWidget {
  const PlatformLab({super.key});
  @override
  ConsumerState<PlatformLab> createState() => _PlatformLabState();
}

class _PlatformLabState extends ConsumerState<PlatformLab>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!await prepareSettingsPreferences() ||
        !await prepareDesktopWindow() ||
        !await prepareSystemMedia()) {
      return AppExitResponse.cancel;
    }
    await disposeSystemMedia();
    await disposeTray();
    await disposeDesktopWindow();
    await disposeSettingsPreferences();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      SystemMediaRuntime.controller?.visibilityChanged(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appAppearanceProvider).value;
    return KoiInputDensity(
      density: appearance?.automaticDensity == true
          ? null
          : (appearance?.density ?? KoiDensity.comfortable),
      builder: (context, effectiveDensity) => MaterialApp(
        onGenerateTitle: (context) =>
            AppLocalizations.of(context)!.platformCapabilities,
        theme: AppTheme.build(
          accent: appearance?.accent ?? KoiAccent.moss,
          density: effectiveDensity,
        ),
        darkTheme: AppTheme.build(
          brightness: Brightness.dark,
          accent: appearance?.accent ?? KoiAccent.moss,
          density: effectiveDensity,
        ),
        themeMode: appearance?.themeMode ?? ThemeMode.system,
        locale: appearance?.locale,
        localeListResolutionCallback: resolveKoiLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          KoiUiLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)!.platformCapabilities),
            ),
            body: ListView(
              children: [
                for (final page in <(String, WidgetBuilder)>[
                  (
                    AppLocalizations.of(context)!.settingsTitle,
                    buildSettingsPage,
                  ),
                  (
                    AppLocalizations.of(context)!.platformDesktopWindow,
                    buildDesktopWindowPage,
                  ),
                  (
                    AppLocalizations.of(context)!.platformSystemTray,
                    buildTrayPage,
                  ),
                  (
                    AppLocalizations.of(context)!.platformSystemMedia,
                    buildSystemMediaPage,
                  ),
                  (
                    AppLocalizations.of(context)!.platformMiniPlayer,
                    buildMiniPlayerPage,
                  ),
                  (
                    AppLocalizations.of(context)!.platformHomeWidget,
                    buildHomeWidgetPage,
                  ),
                ])
                  ListTile(
                    title: Text(page.$1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: page.$2)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
