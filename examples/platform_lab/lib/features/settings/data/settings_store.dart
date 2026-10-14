import 'package:platform_lab/core/preferences/ui_preferences_store.dart';
import 'package:platform_lab/features/settings/data/settings_store_native.dart'
    if (dart.library.js_interop) 'package:platform_lab/features/settings/data/settings_store_web.dart'
    as platform;

Future<UiPreferencesStore> openSettingsStore() => platform.open();
