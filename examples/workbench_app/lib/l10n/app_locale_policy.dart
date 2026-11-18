import 'package:flutter/widgets.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/l10n/generated/app_localizations.dart';

/// App policy; available languages are derived from the ARB-generated catalog.
final appLocalePolicy = KoiLocalePolicy(
  supportedLocales: AppLocalizations.supportedLocales,
  fallbackLocale: const Locale('zh'),
  nativeNames: const {'en': 'English', 'zh': '简体中文', 'zh-Hant': '繁體中文'},
);
