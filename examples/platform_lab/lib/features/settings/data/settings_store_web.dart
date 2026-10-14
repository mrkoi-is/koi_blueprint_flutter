import 'dart:convert';

import 'package:web/web.dart' as web;

import 'package:platform_lab/core/preferences/ui_preferences_store.dart';

Future<UiPreferencesStore> open() async => BrowserUiPreferencesStore();

final class BrowserUiPreferencesStore implements UiPreferencesStore {
  BrowserUiPreferencesStore({this.key = 'koi.workbench.ui-preferences.v1'});
  final String key;
  bool _closed = false;
  @override
  Future<Map<String, Object?>> read() async {
    if (_closed) throw StateError('Preferences are closed');
    final raw = web.window.localStorage.getItem(key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['schema'] != 1) {
      throw const FormatException('Unknown preferences schema');
    }
    return Map<String, Object?>.from(decoded['values'] as Map);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    if (_closed) throw StateError('Preferences are closed');
    web.window.localStorage.setItem(
      key,
      jsonEncode({'schema': 1, 'values': values}),
    );
  }

  @override
  Future<void> close() async => _closed = true;
}
