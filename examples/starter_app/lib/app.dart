import 'package:koi_core/koi_core.dart';
import 'package:starter_app/core/capabilities/app_capabilities.dart';

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:starter_app/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:starter_app/core/router/app_routes.dart';
import 'package:starter_app/core/preferences/appearance_providers.dart';
import 'package:starter_app/core/capabilities/installed_capabilities.dart';

class StarterApp extends ConsumerStatefulWidget {
  const StarterApp({super.key});
  @override
  ConsumerState<StarterApp> createState() => _StarterAppState();
}

class _StarterAppState extends ConsumerState<StarterApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = GoRouter(routes: $appRoutes);
  late final void Function() _detachNavigation;
  Future<void>? _closing;
  Future<void> _close() => _closing ??= disposeInstalledCapabilities();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detachNavigation = CapabilityNavigation.instance.attach((id) async {
      if (!mounted || _closing != null) return false;
      // Consume an unavailable destination without blocking later valid intents.
      if (!appCapabilities.any((capability) => capability.id == id)) {
        return true;
      }
      final location = '/capabilities/$id';
      if (_router.routeInformationProvider.value.uri.path != location) {
        _router.go(location);
      }
      return true;
    });
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!await ref.read(appAppearanceProvider.notifier).flush() ||
        !await prepareInstalledCapabilities()) {
      return AppExitResponse.cancel;
    }
    await _close();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachNavigation();
    _router.dispose();
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appAppearanceProvider).value;
    return KoiInputDensity(
      density: appearance?.automaticDensity == true
          ? null
          : (appearance?.density ?? KoiDensity.comfortable),
      builder: (context, effectiveDensity) => MaterialApp.router(
        title: 'Starter App',
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
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          KoiUiLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: resolveKoiLocale,
        routerConfig: _router,
        builder: (context, child) => Column(
          children: [
            if (appearance?.saveError != null)
              MaterialBanner(
                content: Text(AppLocalizations.of(context)!.settingsSaveError),
                actions: [
                  TextButton(
                    onPressed: ref.read(appAppearanceProvider.notifier).retry,
                    child: Text(AppLocalizations.of(context)!.settingsRetry),
                  ),
                ],
              ),
            Expanded(child: child ?? const SizedBox()),
          ],
        ),
      ),
    );
  }
}
