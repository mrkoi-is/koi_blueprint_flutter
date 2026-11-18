import 'package:flutter/widgets.dart';
import 'package:koi_ui/l10n/generated/koi_ui_localizations.dart';

export 'generated/koi_ui_localizations.dart';
export 'koi_locale_policy.dart';

/// Chinese remains the fallback for hosts that do not install our delegate.
/// App-specific wording can still override each component's label parameter.
abstract final class KoiUiStrings {
  static KoiUiLocalizations of(BuildContext context) =>
      Localizations.of<KoiUiLocalizations>(context, KoiUiLocalizations) ??
      lookupKoiUiLocalizations(const Locale('zh'));
}
