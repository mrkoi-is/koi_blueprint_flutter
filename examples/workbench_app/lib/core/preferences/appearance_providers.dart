import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
part 'appearance_providers.g.dart';

@immutable
class AppAppearanceState {
  const AppAppearanceState({
    this.locale,
    this.accent = KoiAccent.moss,
    this.themeMode,
    this.density,
    this.automaticDensity = false,
    this.saveError,
  });
  final Locale? locale;
  final KoiAccent accent;
  final ThemeMode? themeMode;
  final KoiDensity? density;
  final bool automaticDensity;
  final String? saveError;
  AppAppearanceState copyWith({
    Locale? locale,
    bool clearLocale = false,
    KoiAccent? accent,
    ThemeMode? themeMode,
    KoiDensity? density,
    bool? automaticDensity,
    String? saveError,
  }) => AppAppearanceState(
    locale: clearLocale ? null : locale ?? this.locale,
    accent: accent ?? this.accent,
    themeMode: themeMode ?? this.themeMode,
    density: density ?? this.density,
    automaticDensity: automaticDensity ?? this.automaticDensity,
    saveError: saveError,
  );
}

@Riverpod(keepAlive: true)
UiPreferencesStore uiPreferencesStore(Ref ref) => UiPreferencesRuntime.store;

@Riverpod(keepAlive: true)
class AppAppearance extends _$AppAppearance {
  Map<String, Object?> _values = {};
  Future<void>? _pending;
  int _revision = 0;
  bool _saved = true;
  bool _loadFailed = false;
  @override
  Future<AppAppearanceState> build() async {
    final flushCallback = flush;
    UiPreferencesRuntime.flush = flushCallback;
    ref.onDispose(() {
      if (UiPreferencesRuntime.flush == flushCallback) {
        UiPreferencesRuntime.flush = null;
      }
    });
    try {
      _values = await ref.read(uiPreferencesStoreProvider).read();
      _loadFailed = false;
      return AppAppearanceState(
        locale: switch (_values['locale']) {
          'en' => const Locale('en'),
          'zh' => const Locale('zh'),
          'zh-Hant' => const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          ),
          _ => null,
        },
        accent:
            KoiAccent.values
                .where((v) => v.name == _values['accent'])
                .firstOrNull ??
            KoiAccent.moss,
        themeMode: ThemeMode.values
            .where((v) => v.name == _values['themeMode'])
            .firstOrNull,
        automaticDensity: _values['automaticDensity'] == true,
        density: KoiDensity.values
            .where((v) => v.name == _values['density'])
            .firstOrNull,
      );
    } catch (error) {
      _loadFailed = true;
      return AppAppearanceState(saveError: '$error');
    }
  }

  void apply({required Locale? locale, required KoiAccent accent}) {
    final current = state.value;
    if (current == null) return;
    _update(
      current.copyWith(
        locale: locale,
        clearLocale: locale == null,
        accent: accent,
      ),
    );
  }

  void setLocale(Locale? locale) {
    final current = state.value;
    if (current != null) {
      _update(current.copyWith(locale: locale, clearLocale: locale == null));
    }
  }

  void setAccent(KoiAccent accent) {
    final current = state.value;
    if (current != null) _update(current.copyWith(accent: accent));
  }

  void setThemeMode(ThemeMode themeMode) {
    final current = state.value;
    if (current != null) _update(current.copyWith(themeMode: themeMode));
  }

  void setDensity(KoiDensity density) {
    final current = state.value;
    if (current != null) {
      _update(current.copyWith(density: density, automaticDensity: false));
    }
  }

  void setAutomaticDensity() {
    final current = state.value;
    if (current != null) _update(current.copyWith(automaticDensity: true));
  }

  void restoreDefaults() => _update(
    const AppAppearanceState(
      themeMode: ThemeMode.system,
      density: KoiDensity.comfortable,
    ),
  );
  void _update(AppAppearanceState next) {
    _loadFailed = false;
    final revision = ++_revision;
    _values = {
      ..._values,
      'locale': next.locale?.toLanguageTag(),
      'accent': next.accent.name,
      'themeMode': next.themeMode?.name,
      'density': next.density?.name,
      'automaticDensity': next.automaticDensity,
    };
    final values = Map<String, Object?>.unmodifiable(_values);
    final store = ref.read(uiPreferencesStoreProvider);
    state = AsyncData(next);
    _saved = false;
    _pending = (_pending ?? Future<void>.value()).then((_) async {
      try {
        await store.write(values);
        if (revision == _revision) _saved = true;
      } catch (error) {
        if (ref.mounted && revision == _revision) {
          state = AsyncData(next.copyWith(saveError: '$error'));
        }
      }
    });
  }

  void retry() {
    if (_loadFailed) {
      ref.invalidateSelf();
      return;
    }
    final current = state.value;
    if (current != null) _update(current.copyWith());
  }

  Future<bool> flush() async {
    if (_pending case final pending?) await pending;
    return _saved;
  }
}

// Compatibility for the existing workbench bootstrap and downstream imports.
final workbenchAppearanceProvider = appAppearanceProvider;
typedef WorkbenchAppearanceState = AppAppearanceState;
