import 'package:database_lab/l10n/generated/app_localizations.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:database_lab/features/library/presentation/screens/library_page.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

class DatabaseLabApp extends StatelessWidget {
  const DatabaseLabApp({required this.availability, super.key, this.locale});
  final DatabaseAvailability availability;
  final Locale? locale;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Database Lab',
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: locale,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: LibraryPage(availability: availability),
  );
}
