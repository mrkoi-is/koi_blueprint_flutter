import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/settings/presentation/providers/settings_providers.dart';
import 'package:platform_lab/l10n/generated/app_localizations.dart';

Widget buildSettingsPage(BuildContext context) => const SettingsPage();

/// Search is ephemeral; all persisted choices belong to the host appearance owner.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _query = '';
  bool _matches(String title, String description) =>
      '$title $description'.toLowerCase().contains(_query.toLowerCase().trim());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(appAppearanceProvider);
    final notifier = ref.read(appAppearanceProvider.notifier);
    final value = state.value;
    final groups = <(String, List<Widget>)>[
      (
        l.settingsLanguageGroup,
        [
          if (_matches(l.settingsLanguage, l.settingsLanguageDescription))
            _choice<String>(
              title: l.settingsLanguage,
              description: l.settingsLanguageDescription,
              selected: value?.locale?.toLanguageTag() ?? 'system',
              choices: {
                'system': l.settingsSystem,
                'zh': '简体中文',
                'zh-Hant': '繁體中文',
                'en': 'English',
              },
              onChanged: value == null
                  ? null
                  : (id) => notifier.setLocale(switch (id) {
                      'zh' => const Locale('zh'),
                      'zh-Hant' => const Locale.fromSubtags(
                        languageCode: 'zh',
                        scriptCode: 'Hant',
                      ),
                      'en' => const Locale('en'),
                      _ => null,
                    }),
            ),
        ],
      ),
      (
        l.settingsAppearanceGroup,
        [
          if (_matches(l.settingsTheme, l.settingsThemeDescription))
            _choice<ThemeMode>(
              title: l.settingsTheme,
              description: l.settingsThemeDescription,
              selected: value?.themeMode ?? ThemeMode.system,
              choices: {
                ThemeMode.system: l.settingsSystem,
                ThemeMode.light: l.settingsLight,
                ThemeMode.dark: l.settingsDark,
              },
              onChanged: value == null ? null : notifier.setThemeMode,
            ),
          if (_matches(l.settingsDensity, l.settingsDensityDescription))
            _choice<KoiDensityMode>(
              title: l.settingsDensity,
              description: l.settingsDensityDescription,
              selected: value?.automaticDensity == true
                  ? KoiDensityMode.automatic
                  : value?.density == KoiDensity.compact
                  ? KoiDensityMode.compact
                  : KoiDensityMode.comfortable,
              choices: {
                KoiDensityMode.automatic: l.settingsDensityAutomatic,
                KoiDensityMode.comfortable: l.settingsComfortable,
                KoiDensityMode.compact: l.settingsCompact,
              },
              onChanged: value == null
                  ? null
                  : (mode) {
                      if (mode == KoiDensityMode.automatic) {
                        notifier.setAutomaticDensity();
                      } else {
                        notifier.setDensity(
                          mode == KoiDensityMode.compact
                              ? KoiDensity.compact
                              : KoiDensity.comfortable,
                        );
                      }
                    },
            ),
          if (_matches(l.settingsAccent, l.settingsAccentDescription))
            _choice<KoiAccent>(
              title: l.settingsAccent,
              description: l.settingsAccentDescription,
              selected: value?.accent ?? KoiAccent.moss,
              choices: {
                KoiAccent.moss: l.settingsMoss,
                KoiAccent.blue: l.settingsBlue,
                KoiAccent.violet: l.settingsViolet,
              },
              onChanged: value == null ? null : notifier.setAccent,
            ),
        ],
      ),
    ];
    final visible = groups.where((group) => group.$2.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KoiSearchField(
                hintText: l.settingsSearch,
                onChanged: (text) => setState(() => _query = text),
              ),
              if (state.isLoading) const LinearProgressIndicator(),
              if (value?.saveError != null || state.hasError)
                MaterialBanner(
                  content: Text(l.settingsSaveError),
                  actions: [
                    TextButton(
                      onPressed: notifier.retry,
                      child: Text(l.settingsRetry),
                    ),
                  ],
                ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.settingsNoResults),
                ),
              for (final group in visible) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                  child: Text(
                    group.$1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...group.$2,
              ],
              const SizedBox(height: 24),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  onPressed: value == null
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l.settingsReset),
                              content: Text(l.settingsResetDescription),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l.settingsCancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l.settingsReset),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            notifier.restoreDefaults();
                          }
                        },
                  child: Text(l.settingsReset),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice<T extends Object>({
    required String title,
    required String description,
    required T selected,
    required Map<T, String> choices,
    required ValueChanged<T>? onChanged,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(description),
          const SizedBox(height: 8),
          Semantics(
            label: title,
            child: DropdownButton<T>(
              isExpanded: true,
              value: selected,
              items: [
                for (final choice in choices.entries)
                  DropdownMenuItem(
                    value: choice.key,
                    child: Text(choice.value),
                  ),
              ],
              onChanged: onChanged == null
                  ? null
                  : (value) {
                      if (value != null) onChanged(value);
                    },
            ),
          ),
        ],
      ),
    ),
  );
}
