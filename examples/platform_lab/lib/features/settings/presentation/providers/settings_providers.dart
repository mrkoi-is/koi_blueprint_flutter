import 'package:platform_lab/core/preferences/ui_preferences_store.dart';
import 'package:platform_lab/features/settings/data/settings_store.dart';
export 'package:platform_lab/core/preferences/appearance_providers.dart';

bool _opened = false;
Future<void> initializeSettingsPreferences() async {
  if (_opened) return;
  if (!UiPreferencesRuntime.managedByBootstrap) {
    UiPreferencesRuntime.store = await openSettingsStore();
  }
  _opened = true;
}

Future<bool> prepareSettingsPreferences() async =>
    await UiPreferencesRuntime.flush?.call() ?? true;
Future<void> disposeSettingsPreferences() async {
  if (!_opened) return;
  _opened = false;
  if (!UiPreferencesRuntime.managedByBootstrap) {
    final store = UiPreferencesRuntime.store;
    UiPreferencesRuntime.store = MemoryUiPreferencesStore();
    await store.close();
  }
}
