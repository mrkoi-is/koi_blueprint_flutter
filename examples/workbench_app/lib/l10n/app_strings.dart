import 'package:flutter/widgets.dart';

import 'package:workbench_app/l10n/generated/app_localizations.dart';
export 'package:workbench_app/l10n/generated/app_localizations.dart';

extension WorkbenchStrings on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('zh'));
}
