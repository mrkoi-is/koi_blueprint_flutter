import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
import 'package:workbench_app/features/workspace/presentation/providers/appearance_providers.dart';

class _Store implements UiPreferencesStore {
  Map<String, Object?> values = {};
  bool failRead = false;
  bool failWrite = false;
  final writes = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> read() async {
    if (failRead) throw StateError('read denied');
    return Map.of(values);
  }

  @override
  Future<void> write(Map<String, Object?> next) async {
    if (failWrite) throw StateError('write denied');
    writes.add(next);
    values = Map.of(next);
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'system locale default, roundtrip and unknown fields survive writes',
    () async {
      final store = _Store()..values = {'future': true};
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(workbenchAppearanceProvider.future)).locale,
        isNull,
      );
      final notifier = container.read(workbenchAppearanceProvider.notifier);
      notifier.setLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      notifier.setAccent(KoiAccent.violet);
      expect(await notifier.flush(), isTrue);
      expect(store.values, {
        'future': true,
        'locale': 'zh-Hant',
        'accent': 'violet',
        'themeMode': null,
        'density': null,
        'automaticDensity': false,
      });
      final restored = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restored.dispose);
      final state = await restored.read(workbenchAppearanceProvider.future);
      expect(state.locale!.scriptCode, 'Hant');
      expect(state.accent, KoiAccent.violet);
    },
  );

  test(
    'automatic density is explicit, persistent, and manual choice wins',
    () async {
      final store = _Store()..values = {'density': 'compact'};
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final initial = await container.read(workbenchAppearanceProvider.future);
      expect(initial.density, KoiDensity.compact);
      expect(initial.automaticDensity, isFalse);
      final notifier = container.read(workbenchAppearanceProvider.notifier);
      notifier.setAutomaticDensity();
      expect(await notifier.flush(), isTrue);
      expect(store.values['automaticDensity'], isTrue);
      final restored = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restored.dispose);
      expect(
        (await restored.read(workbenchAppearanceProvider.future))
            .automaticDensity,
        isTrue,
      );
      notifier.setDensity(KoiDensity.comfortable);
      expect(await notifier.flush(), isTrue);
      expect(store.values['automaticDensity'], isFalse);
      expect(store.values['density'], 'comfortable');
    },
  );

  test(
    'write failure stays visible and retry commits the latest draft',
    () async {
      final store = _Store()..failWrite = true;
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(workbenchAppearanceProvider.future);
      final notifier = container.read(workbenchAppearanceProvider.notifier);
      notifier.setAccent(KoiAccent.blue);
      expect(await notifier.flush(), isFalse);
      expect(
        container.read(workbenchAppearanceProvider).value!.saveError,
        contains('write denied'),
      );
      store.failWrite = false;
      notifier.retry();
      expect(await notifier.flush(), isTrue);
      expect(store.values['accent'], 'blue');
      expect(
        container.read(workbenchAppearanceProvider).value!.saveError,
        isNull,
      );
    },
  );

  test('corrupt preferences fall back and remain recoverable', () async {
    final store = _Store()..failRead = true;
    final container = ProviderContainer(
      overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final state = await container.read(workbenchAppearanceProvider.future);
    expect(state.locale, isNull);
    expect(state.accent, KoiAccent.moss);
    expect(state.saveError, contains('read denied'));
  });
  test(
    'failed load retry rereads without replacing unrelated persisted values',
    () async {
      final store = _Store()
        ..failRead = true
        ..values = {'accent': 'blue', 'future': 1};
      final container = ProviderContainer(
        overrides: [uiPreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(appAppearanceProvider.future);
      store.failRead = false;
      container.read(appAppearanceProvider.notifier).retry();
      final restored = await container.read(appAppearanceProvider.future);
      expect(restored.accent, KoiAccent.blue);
      expect(store.writes, isEmpty);
      expect(store.values['future'], 1);
    },
  );
}
