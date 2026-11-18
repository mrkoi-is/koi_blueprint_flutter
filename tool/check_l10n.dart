import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Source checks deliberately ignore generated missing-message reports: an old
/// empty report must never hide a newly missing translation. Flutter gen-l10n
/// remains responsible for parsing ICU expressions and generating typed accessors.
List<String> checkLocalizations(Directory member) {
  final configFile = File('${member.path}/l10n.yaml');
  if (!configFile.existsSync()) return [];
  final issues = <String>[];
  try {
    final config = loadYaml(configFile.readAsStringSync());
    if (config is! YamlMap) {
      throw const FormatException('Expected YAML mapping');
    }
    final directory = Directory(
      '${member.path}/${config['arb-dir'] ?? 'lib/l10n'}',
    );
    final template = File(
      '${directory.path}/${config['template-arb-file'] ?? 'app_en.arb'}',
    );
    final source = _readArb(template);
    final expected = _messageKeys(source);
    if (expected.isEmpty) {
      issues.add('${template.path}: template has no messages');
    }
    final locales = <String>{};
    final bundles =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.arb'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in bundles) {
      try {
        final messages = _readArb(file);
        final locale = messages['@@locale'];
        if (locale is! String || locale.trim().isEmpty) {
          issues.add('${file.path}: @@locale must be a nonempty language tag');
        } else {
          if (!locales.add(locale.replaceAll('-', '_'))) {
            issues.add('${file.path}: duplicate locale $locale');
          }
          if (!file.path.endsWith('_${locale.replaceAll('-', '_')}.arb')) {
            issues.add('${file.path}: filename must end in _$locale.arb');
          }
        }
        final keys = _messageKeys(messages);
        for (final key in expected.difference(keys)) {
          issues.add('${file.path}: missing translation $key');
        }
        for (final key in keys.difference(expected)) {
          issues.add(
            '${file.path}: unknown translation $key (absent from template)',
          );
        }
        for (final key in keys) {
          final value = messages[key];
          if (value is! String || value.trim().isEmpty) {
            issues.add('${file.path}: $key must be a nonempty string');
          }
        }
        for (final key in messages.keys.where(
          (key) => key.startsWith('@') && !key.startsWith('@@'),
        )) {
          if (!keys.contains(key.substring(1))) {
            issues.add('${file.path}: orphan metadata $key');
          }
          final metadata = messages[key];
          if (metadata is! Map<String, dynamic>) {
            issues.add('${file.path}: $key must be an object');
            continue;
          }
          final placeholders = metadata['placeholders'];
          if (placeholders != null && placeholders is! Map<String, dynamic>) {
            issues.add('${file.path}: $key placeholders must be an object');
            continue;
          }
          if (placeholders is Map<String, dynamic> &&
              file.path != template.path) {
            final templateMetadata = source[key];
            final base = templateMetadata is Map<String, dynamic>
                ? templateMetadata['placeholders']
                : null;
            if (base is! Map<String, dynamic> ||
                !_sameKeys(placeholders, base)) {
              issues.add(
                '${file.path}: $key placeholder names differ from template',
              );
            } else {
              for (final name in placeholders.keys) {
                final translated = placeholders[name];
                final original = base[name];
                if (translated is! Map<String, dynamic> ||
                    original is! Map<String, dynamic> ||
                    (translated.containsKey('type') &&
                        translated['type'] != original['type'])) {
                  issues.add(
                    '${file.path}: $key placeholder $name type differs from template',
                  );
                }
              }
            }
          }
        }
      } on FileSystemException catch (error) {
        issues.add('${file.path}: $error');
      } on FormatException catch (error) {
        issues.add('${file.path}: ${error.message}');
      }
    }
    for (final key in expected) {
      final metadata = source['@$key'];
      if (metadata is! Map<String, dynamic>) continue;
      final placeholders = metadata['placeholders'];
      if (placeholders is! Map<String, dynamic> || placeholders.isEmpty) {
        continue;
      }
      final description = metadata['description'];
      if (description is! String || description.trim().isEmpty) {
        issues.add(
          '${template.path}: @$key requires a description for translators',
        );
      }
      for (final entry in placeholders.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic> ||
            value['type'] is! String ||
            (value['type'] as String).trim().isEmpty) {
          issues.add(
            '${template.path}: @$key placeholder ${entry.key} requires an explicit type',
          );
        }
      }
    }
  } on FileSystemException catch (error) {
    issues.add('${configFile.path}: $error');
  } on FormatException catch (error) {
    issues.add('${configFile.path}: ${error.message}');
  }
  return issues;
}

Map<String, dynamic> _readArb(File file) {
  final text = file.readAsStringSync();
  final value = jsonDecode(text);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('ARB must be a JSON object');
  }
  // jsonDecode accepts duplicate keys; the YAML parser rejects them. JSON is a
  // YAML subset, and JSON syntax has already been checked above.
  loadYaml(text);
  return value;
}

Set<String> _messageKeys(Map<String, dynamic> messages) =>
    messages.keys.where((key) => !key.startsWith('@')).toSet();

bool _sameKeys(Map<String, dynamic> a, Map<String, dynamic> b) =>
    a.length == b.length && a.keys.every(b.containsKey);

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_l10n.dart <workspace-member> ...',
    );
    exitCode = 2;
    return;
  }
  final issues = arguments
      .expand((path) => checkLocalizations(Directory(path)))
      .toList();
  for (final issue in issues) {
    stderr.writeln(issue);
  }
  if (issues.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln(
      'Localization source checks passed. ICU syntax is checked by flutter gen-l10n.',
    );
  }
}
