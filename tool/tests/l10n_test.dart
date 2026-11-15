import 'dart:convert';
import 'dart:io';

import '../check_l10n.dart';

void main() {
  var passed = 0;
  void scenario(String name, void Function(Directory) run) {
    final root = Directory.systemTemp.createTempSync('koi-l10n-');
    try {
      File('${root.path}/l10n.yaml').writeAsStringSync(
        'arb-dir: "translations"\ntemplate-arb-file: app_en.arb\n',
      );
      Directory('${root.path}/translations').createSync();
      write(root, 'en', {
        'greeting': 'Hello {name}',
        '@greeting': {
          'description': 'Welcome the current user by display name.',
          'placeholders': {
            'name': {'type': 'String'},
          },
        },
      });
      write(root, 'zh', {'greeting': '你好，{name}'});
      run(root);
      passed++;
      stdout.writeln('PASS $name');
    } finally {
      root.deleteSync(recursive: true);
    }
  }

  scenario('complete translations may inherit template metadata', (root) {
    require(checkLocalizations(root).isEmpty, 'Valid ARBs must pass');
  });
  scenario('stale empty generated report cannot hide missing source keys', (
    root,
  ) {
    Directory('${root.path}/.dart_tool').createSync();
    File('${root.path}/.dart_tool/untranslated_messages.json')
        .writeAsStringSync('{}');
    write(root, 'zh', {});
    rejects(root, 'missing translation greeting');
  });
  scenario('unknown keys and orphan metadata fail', (root) {
    write(root, 'zh', {'greeting': '你好', 'typo': '文本', '@deleted': {}});
    rejects(root, 'unknown translation typo');
    rejects(root, 'orphan metadata @deleted');
  });
  scenario('blank and non-string translations fail', (root) {
    for (final value in <Object?>['  \n', null, 42]) {
      write(root, 'zh', {'greeting': value});
      rejects(root, 'greeting must be a nonempty string');
    }
  });
  scenario('duplicate JSON keys fail instead of silently overwriting', (root) {
    File('${root.path}/translations/app_zh.arb')
        .writeAsStringSync('{"@@locale":"zh","greeting":"甲","greeting":"乙"}');
    require(checkLocalizations(root).isNotEmpty, 'Duplicate keys must fail');
  });
  scenario('declared placeholders require translator context and types', (
    root,
  ) {
    write(root, 'en', {
      'greeting': 'Hello {name}',
      '@greeting': {
        'placeholders': {'name': <String, Object?>{}},
      },
    });
    rejects(root, 'requires a description');
    rejects(root, 'requires an explicit type');
  });
  scenario('translated placeholder names and types must match', (root) {
    write(root, 'zh', {
      'greeting': '你好，{other}',
      '@greeting': {
        'placeholders': {
          'other': {'type': 'String'},
        },
      },
    });
    rejects(root, 'placeholder names differ');
    write(root, 'zh', {
      'greeting': '你好，{name}',
      '@greeting': {
        'placeholders': {
          'name': {'type': 'int'},
        },
      },
    });
    rejects(root, 'type differs');
  });
  scenario('malformed metadata fails with a diagnostic', (root) {
    for (final metadata in <Object?>[
      [],
      'invalid',
      {'placeholders': <Object?>[]},
    ]) {
      write(root, 'zh', {'greeting': '你好', '@greeting': metadata});
      require(
        checkLocalizations(root).isNotEmpty,
        'Malformed metadata must fail',
      );
    }
  });
  scenario('wrong locale identity and malformed files fail', (root) {
    write(root, 'zh', {'@@locale': 'fr', 'greeting': '你好'});
    rejects(root, 'filename must end');
    File('${root.path}/translations/app_zh.arb').writeAsStringSync('[]');
    rejects(root, 'ARB must be a JSON object');
    File('${root.path}/translations/app_zh.arb').writeAsStringSync('{');
    require(checkLocalizations(root).isNotEmpty, 'Broken JSON must fail');
  });
  scenario('missing template and malformed config fail', (root) {
    File('${root.path}/translations/app_en.arb').deleteSync();
    require(checkLocalizations(root).isNotEmpty, 'Missing template must fail');
    File('${root.path}/l10n.yaml').writeAsStringSync('[]');
    rejects(root, 'Expected YAML mapping');
  });
  stdout.writeln('$passed localization regression cases passed.');
}

void write(Directory root, String locale, Map<String, Object?> messages) {
  File('${root.path}/translations/app_$locale.arb')
      .writeAsStringSync(jsonEncode({'@@locale': locale, ...messages}));
}

void rejects(Directory root, String message) => require(
  checkLocalizations(root).any((issue) => issue.contains(message)),
  'Expected $message; got ${checkLocalizations(root)}',
);

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
