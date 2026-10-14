import 'package:flutter/widgets.dart';
import 'package:koi_ui/l10n/generated/koi_ui_localizations.dart';

export 'generated/koi_ui_localizations.dart';

/// Chinese remains the fallback for hosts that do not install our delegate.
/// App-specific wording can still override each component's label parameter.
abstract final class KoiUiStrings {
  static KoiUiLocalizations of(BuildContext context) =>
      Localizations.of<KoiUiLocalizations>(context, KoiUiLocalizations) ??
      lookupKoiUiLocalizations(const Locale('zh'));
}

/// Shared matching policy; ownership of the selected locale stays with the App.
Locale resolveKoiLocale(List<Locale>? requested, Iterable<Locale> supported) {
  final locales = supported.toList();
  for (final locale in requested ?? const <Locale>[]) {
    if (locale.languageCode == 'zh') {
      final traditional =
          locale.scriptCode == 'Hant' ||
          (locale.scriptCode == null &&
              const {'TW', 'HK', 'MO'}.contains(locale.countryCode));
      if (traditional) {
        for (final candidate in locales) {
          if (candidate.languageCode == 'zh' &&
              candidate.scriptCode == 'Hant') {
            return candidate;
          }
        }
      }
      for (final candidate in locales) {
        if (candidate.languageCode == 'zh' && candidate.scriptCode != 'Hant') {
          return candidate;
        }
      }
    }
    for (final candidate in locales) {
      if (candidate == locale) return candidate;
    }
    for (final candidate in locales) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  return locales.firstWhere(
    (locale) => locale.languageCode == 'zh' && locale.scriptCode != 'Hant',
    orElse: () => locales.isEmpty ? const Locale('zh') : locales.first,
  );
}
