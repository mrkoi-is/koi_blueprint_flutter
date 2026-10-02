import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/features/workspace/presentation/providers/appearance_providers.dart';
import 'package:workbench_app/l10n/app_strings.dart';

/// Draft selection is local to the dialog; Cancel never changes preferences.
Future<void> showAppearanceDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(workbenchAppearanceProvider).value;
  if (current == null) return;
  var locale = current.locale?.toLanguageTag() ?? 'system';
  var accent = current.accent;
  final apply = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.l10n.settings),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('appearance-locale'),
              initialValue: locale,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.l10n.language),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(context.l10n.systemLanguage),
                ),
                const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                const DropdownMenuItem(value: 'zh-Hant', child: Text('繁體中文')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) => setState(() => locale = value ?? 'system'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<KoiAccent>(
              key: const ValueKey('appearance-accent'),
              initialValue: accent,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.l10n.accent),
              items: [
                DropdownMenuItem(
                  value: KoiAccent.moss,
                  child: Text(context.l10n.moss),
                ),
                DropdownMenuItem(
                  value: KoiAccent.blue,
                  child: Text(context.l10n.blue),
                ),
                DropdownMenuItem(
                  value: KoiAccent.violet,
                  child: Text(context.l10n.violet),
                ),
              ],
              onChanged: (value) =>
                  setState(() => accent = value ?? KoiAccent.moss),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.apply),
          ),
        ],
      ),
    ),
  );
  if (apply != true || !context.mounted) return;
  final notifier = ref.read(workbenchAppearanceProvider.notifier);
  notifier.apply(
    locale: switch (locale) {
      'en' => const Locale('en'),
      'zh' => const Locale('zh'),
      'zh-Hant' => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      _ => null,
    },
    accent: accent,
  );
}
