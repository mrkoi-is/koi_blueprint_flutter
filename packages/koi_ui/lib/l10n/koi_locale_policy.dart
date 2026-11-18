import 'package:flutter/widgets.dart';

/// App-owned locale configuration, shared by matching, settings and persistence.
/// The generated supported locales remain the source of truth for availability.
final class KoiLocalePolicy {
  KoiLocalePolicy({
    required Iterable<Locale> supportedLocales,
    required this.fallbackLocale,
    Map<String, String> nativeNames = const {},
  }) : supportedLocales = List.unmodifiable(supportedLocales),
       nativeNames = Map.unmodifiable(nativeNames) {
    if (this.supportedLocales.isEmpty ||
        !this.supportedLocales.contains(fallbackLocale)) {
      throw ArgumentError('The fallback locale must be supported by the App.');
    }
  }

  final List<Locale> supportedLocales;
  final Locale fallbackLocale;
  final Map<String, String> nativeNames;

  /// Unknown or removed preferences return to following the system.
  /// Both BCP 47 tags and legacy ARB-style tags are accepted.
  Locale? fromTag(Object? tag) {
    if (tag is! String) return null;
    final normalized = tag.replaceAll('_', '-').toLowerCase();
    for (final locale in supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() == normalized) return locale;
    }
    return null;
  }

  String label(Locale locale) =>
      nativeNames[locale.toLanguageTag()] ?? locale.toLanguageTag();

  /// Signature matches MaterialApp.localeListResolutionCallback.
  Locale resolve(List<Locale>? requested, Iterable<Locale> supported) =>
      resolveKoiLocale(requested, supported, fallbackLocale: fallbackLocale);
}

/// Chinese regions imply a script only when no explicit script was requested.
/// The optional fallback preserves the historical Chinese default for old hosts.
Locale resolveKoiLocale(
  List<Locale>? requested,
  Iterable<Locale> supported, {
  Locale fallbackLocale = const Locale('zh'),
}) {
  final locales = supported.toList();
  for (final locale in requested ?? const <Locale>[]) {
    if (locales.contains(locale)) return locale;
    if (locale.languageCode == 'zh') {
      final script =
          locale.scriptCode ??
          (const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
              ? 'Hant'
              : 'Hans');
      for (final candidate in locales) {
        if (candidate.languageCode == 'zh' && candidate.scriptCode == script) {
          return candidate;
        }
      }
      // The language-only Chinese bundle is the generic fallback (Simplified
      // Chinese in the blueprint), not an arbitrary region/script variant.
      for (final candidate in locales) {
        if (candidate.languageCode == 'zh' && candidate.scriptCode == null) {
          return candidate;
        }
      }
    } else if (locale.scriptCode != null) {
      for (final candidate in locales) {
        if (candidate.languageCode == locale.languageCode &&
            candidate.scriptCode == locale.scriptCode) {
          return candidate;
        }
      }
    }
    for (final candidate in locales) {
      if (candidate.languageCode == locale.languageCode &&
          candidate.countryCode == locale.countryCode) {
        return candidate;
      }
    }
    for (final candidate in locales) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  if (locales.contains(fallbackLocale)) return fallbackLocale;
  return locales.isEmpty ? fallbackLocale : locales.first;
}
