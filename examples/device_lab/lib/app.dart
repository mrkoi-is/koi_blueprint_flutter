import 'package:device_lab/l10n/generated/app_localizations.dart';
import 'package:device_lab/features/devices/presentation/screens/device_page.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

class DeviceLabApp extends StatelessWidget {
  const DeviceLabApp({super.key, this.locale});
  final Locale? locale;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Device Lab',
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: locale,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: const DevicePage(),
  );
}
