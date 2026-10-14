import 'dart:convert';
import 'dart:io';

import '../architecture/checker.dart';

int _passed = 0;

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void test(String name, void Function() run) {
  run();
  _passed++;
  stdout.writeln('PASS $name');
}

final class Fixture {
  Fixture()
    : root = Directory.systemTemp.createTempSync('koi-architecture-test-');
  final Directory root;
  final List<WorkspaceMember> members = [];
  void member(String name, String path, {Set<String> dependencies = const {}}) {
    members.add(
      WorkspaceMember(name: name, path: path, dependencies: dependencies),
    );
  }

  void source(String path, String source) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  }

  List<ArchitectureIssue> check() => checkWorkspace(root, members);
  void dispose() => root.deleteSync(recursive: true);
}

void ruleCase(
  String rule,
  String description,
  String source, {
  required bool rejected,
  String path =
      'apps/demo/lib/features/tasks/presentation/providers/tasks.dart',
  void Function(Fixture fixture)? setup,
}) {
  test('$rule $description', () {
    final fixture = Fixture();
    try {
      fixture.member('demo', 'apps/demo');
      setup?.call(fixture);
      fixture.source(path, source);
      final issues = fixture.check();
      expect(
        issues.any((issue) => issue.rule == rule) == rejected,
        '$rule expected rejected=$rejected, got ${issues.join('\n')}',
      );
      expect(
        !issues.any((issue) => issue.rule == 'ARCH000'),
        'Fixture must parse: $issues',
      );
    } finally {
      fixture.dispose();
    }
  });
}

void main() {
  for (final library in [
    'io',
    'ffi',
    'html',
    'js',
    'js_util',
    'js_interop',
    'js_interop_unsafe',
  ]) {
    ruleCase(
      'ARCH003',
      'reject pure UI platform library dart:$library',
      "import 'dart:$library';",
      rejected: true,
      path: 'packages/koi_ui/lib/src/widgets/tile.dart',
      setup: (f) =>
          f.member('koi_ui', 'packages/koi_ui', dependencies: {'flutter'}),
    );
  }
  for (final package in [
    'file_selector',
    'file_selector_web',
    'cross_file',
    'media_kit',
    'media_kit_video',
    'media_kit_libs_android_video',
    'web',
    'ffi',
    'riverpod',
  ]) {
    ruleCase(
      'ARCH003',
      'reject pure UI adapter import $package',
      "import 'package:$package/implementation.dart';",
      rejected: true,
      path: 'packages/koi_ui/lib/src/widgets/tile.dart',
      setup: (f) =>
          f.member('koi_ui', 'packages/koi_ui', dependencies: {'flutter'}),
    );
    test('ARCH003 reject pure UI runtime dependency $package', () {
      final f = Fixture();
      try {
        f.member(
          'koi_ui',
          'packages/koi_ui',
          dependencies: {'flutter', package},
        );
        expect(
          f.check().any(
            (issue) => issue.rule == 'ARCH003' && issue.target == package,
          ),
          'A UI dependency must fail even before adapter source is added',
        );
      } finally {
        f.dispose();
      }
    });
  }
  ruleCase(
    'ARCH003',
    'reject conditional IO export in pure UI',
    "export 'noop.dart' if (dart.library.io) 'dart:io';",
    rejected: true,
    path: 'packages/koi_ui/lib/koi_ui.dart',
    setup: (f) => f.member('koi_ui', 'packages/koi_ui'),
  );
  ruleCase(
    'ARCH003',
    'allow Material widgets, rendering types and pure Dart models in UI',
    "import 'package:flutter/material.dart'; import 'dart:ui' as ui; import 'package:freezed_annotation/freezed_annotation.dart'; class Tile extends StatelessWidget { const Tile({super.key}); @override Widget build(BuildContext context) => const Material(child: Text('组件')); }",
    rejected: false,
    path: 'packages/koi_ui/lib/src/widgets/tile.dart',
    setup: (f) => f.member(
      'koi_ui',
      'packages/koi_ui',
      dependencies: {'flutter', 'freezed_annotation'},
    ),
  );
  test('ARCH003 UI dependency graph allows Flutter helper but rejects transitive media adapters', () {
    final f = Fixture();
    try {
      f.member('koi_ui', 'packages/koi_ui', dependencies: {'widget_helpers'});
      f.member(
        'widget_helpers',
        'packages/widget_helpers',
        dependencies: {'flutter'},
      );
      f.source(
        'packages/koi_ui/lib/koi_ui.dart',
        "export 'package:widget_helpers/widgets.dart';",
      );
      expect(
        f.check().isEmpty,
        'Pure Flutter widget helpers should remain valid dependencies',
      );
      f.members.last.dependencies.add('media_kit');
      expect(
        f.check().any(
          (issue) =>
              issue.rule == 'ARCH003' && issue.target == 'widget_helpers',
        ),
        'A transitive media adapter must not hide behind a generic helper name',
      );
    } finally {
      f.dispose();
    }
  });
  for (final package in [
    'file_selector',
    'cross_file',
    'media_kit',
    'media_kit_video',
    'web',
  ]) {
    ruleCase(
      'ARCH003',
      'reject domain platform implementation $package',
      "import 'package:$package/implementation.dart';",
      rejected: true,
      path: 'apps/demo/lib/features/workspace/domain/port.dart',
    );
  }
  ruleCase(
    'ARCH003',
    'reject domain JS interop',
    "import 'dart:js_interop';",
    rejected: true,
    path: 'apps/demo/lib/features/workspace/domain/port.dart',
  );
  ruleCase(
    'ARCH007',
    'async provider cannot hide blocking IO behind async keyword',
    "import 'dart:io'; import 'package:riverpod_annotation/riverpod_annotation.dart'; @riverpod Future<bool> exists(Ref ref) async => File('x').existsSync();",
    rejected: true,
  );

  for (final registered in [false, true]) {
    test(
      'ARCH009 ${registered ? 'allow registered' : 'reject orphan'} example template',
      () {
        final fixture = Fixture();
        try {
          fixture.source('examples/template/pubspec.yaml', 'name: template\n');
          if (registered) fixture.member('template', 'examples/template');
          expect(
            fixture.check().any((issue) => issue.rule == 'ARCH009') ==
                !registered,
            'A source template cannot silently leave the checked workspace',
          );
        } finally {
          fixture.dispose();
        }
      },
    );
  }

  ruleCase(
    'ARCH001',
    'reject shared package importing app',
    "import 'package:demo/features/tasks/domain/task.dart';",
    rejected: true,
    path: 'packages/shared/lib/shared.dart',
    setup: (f) => f.member('shared', 'packages/shared'),
  );
  ruleCase(
    'ARCH001',
    'allow app importing shared package',
    "import 'package:shared/shared.dart';",
    rejected: false,
    setup: (f) => f.member('shared', 'packages/shared'),
  );
  test('ARCH001 reject module runtime dependency on sibling module', () {
    final f = Fixture();
    try {
      f.member('alpha', 'examples/demo/modules/alpha', dependencies: {'beta'});
      f.member('beta', 'examples/demo/modules/beta');
      expect(
        f.check().any((e) => e.rule == 'ARCH001'),
        'Sibling module dependency must fail',
      );
    } finally {
      f.dispose();
    }
  });
  for (final source in ['modules/alpha', 'apps/alpha']) {
    test('ARCH001 reject $source runtime dependency on app without import', () {
      final f = Fixture();
      try {
        f.member('alpha', source, dependencies: {'demo'});
        f.member('demo', 'apps/demo');
        expect(
          f.check().any((e) => e.rule == 'ARCH001'),
          'Runtime manifest alone must enforce app boundary',
        );
      } finally {
        f.dispose();
      }
    });
  }
  test(
    'ARCH001 allow app runtime dependency on module and shared contract',
    () {
      final f = Fixture();
      try {
        f.member('demo', 'apps/demo', dependencies: {'alpha', 'contracts'});
        f.member('alpha', 'modules/alpha', dependencies: {'contracts'});
        f.member('contracts', 'packages/contracts');
        expect(f.check().isEmpty, 'Allowed runtime direction must pass');
      } finally {
        f.dispose();
      }
    },
  );
  ruleCase(
    'ARCH002',
    'reject module internal import',
    "import 'package:alpha/src/state.dart';",
    rejected: true,
    setup: (f) => f.member('alpha', 'examples/demo/modules/alpha'),
  );
  ruleCase(
    'ARCH002',
    'allow public module entrypoint',
    "import 'package:alpha/alpha.dart';",
    rejected: false,
    setup: (f) => f.member('alpha', 'examples/demo/modules/alpha'),
  );
  ruleCase(
    'ARCH002',
    'reject relative module internal import',
    "import '../../../modules/alpha/lib/src/state.dart';",
    rejected: true,
    path: 'apps/demo/lib/main.dart',
    setup: (f) => f.member('alpha', 'modules/alpha'),
  );
  ruleCase(
    'ARCH003',
    'reject domain Flutter import',
    "import 'package:flutter/material.dart';",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/domain/task.dart',
  );
  ruleCase(
    'ARCH003',
    'allow domain pure Dart and annotations',
    "import 'dart:collection';\nimport 'package:freezed_annotation/freezed_annotation.dart';",
    rejected: false,
    path: 'apps/demo/lib/features/tasks/domain/task.dart',
  );
  test('ARCH003 allow app domain to import its own domain model', () {
    final f = Fixture();
    try {
      f.member('demo', 'apps/demo', dependencies: {'flutter', 'riverpod'});
      f.source(
        'apps/demo/lib/features/tasks/domain/repository.dart',
        "import 'package:demo/features/tasks/domain/task.dart';",
      );
      expect(
        f.check().isEmpty,
        'Own domain import must ignore app UI dependency',
      );
    } finally {
      f.dispose();
    }
  });
  ruleCase(
    'ARCH003',
    'reject conditional IO in domain',
    "import 'noop.dart' if (dart.library.io) 'dart:io';",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/domain/task.dart',
  );
  test(
    'ARCH003 reject transitive Flutter runtime dependency but ignore test SDK',
    () {
      final f = Fixture();
      try {
        f.member('koi_domain', 'packages/koi_domain', dependencies: {'bridge'});
        f.member('bridge', 'packages/bridge', dependencies: {'flutter'});
        expect(
          f.check().any((e) => e.rule == 'ARCH003'),
          'Transitive UI coupling must fail',
        );
        f.source(
          'packages/pure/pubspec.yaml',
          'name: pure\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n',
        );
        expect(
          readMember(
            f.root,
            '${f.root.path}/packages/pure',
          ).dependencies.isEmpty,
          'Test-only dependencies are not runtime dependencies',
        );
      } finally {
        f.dispose();
      }
    },
  );
  ruleCase(
    'ARCH004',
    'reject provider in application',
    "import 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod int count(Ref ref) => 0;",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/application/tasks.dart',
  );
  ruleCase(
    'ARCH004',
    'allow provider in presentation/providers',
    "import 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod int count(Ref ref) => 0;",
    rejected: false,
  );
  ruleCase(
    'ARCH004',
    'allow core router composition',
    "import 'package:riverpod_annotation/riverpod_annotation.dart';\n@Riverpod(keepAlive: true) int router(Ref ref) => 0;",
    rejected: false,
    path: 'apps/demo/lib/core/router/app_router.dart',
  );
  ruleCase(
    'ARCH005',
    'reject handwritten Provider',
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\nfinal count = Provider<int>((ref) => 0);",
    rejected: true,
  );
  ruleCase(
    'ARCH005',
    'reject prefixed autoDispose factory',
    "import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;\nfinal count = rp.FutureProvider.autoDispose<int>((ref) async => 0);",
    rejected: true,
  );
  ruleCase(
    'ARCH005',
    'allow annotated provider',
    "import 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod int count(Ref ref) => 0;",
    rejected: false,
  );
  ruleCase(
    'ARCH005',
    'ignore strings and unrelated Provider class',
    "class Provider { Provider(); }\nfinal value = Provider();\nconst example = 'StateProvider((ref) => 0)';",
    rejected: false,
  );
  ruleCase(
    'ARCH006',
    'reject page data import',
    "import 'package:demo/features/tasks/data/task_repository.dart';",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH006',
    'reject page network import',
    "import 'package:dio/dio.dart';",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/widgets/task_card.dart',
  );
  ruleCase(
    'ARCH006',
    'allow page provider and domain imports',
    "import 'package:demo/features/tasks/presentation/providers/tasks.dart';\nimport 'package:demo/features/tasks/domain/task.dart';",
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH007',
    'reject synchronous IO in widget build',
    "import 'dart:io';\nclass TasksPage extends StatelessWidget { Widget build(BuildContext context) { return Text(File('sample').readAsStringSync()); } }",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH007',
    'reject synchronous IO through typed variable',
    "import 'dart:io' as io;\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod bool exists(Ref ref) { final file = io.File('sample'); return file.existsSync(); }",
    rejected: true,
  );
  ruleCase(
    'ARCH007',
    'reject synchronous IO through typed provider parameter',
    "import 'dart:io';\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod String contents(Ref ref, File file) => file.readAsStringSync();",
    rejected: true,
  );
  ruleCase(
    'ARCH007',
    'reject prefixed Directory parameter in async provider',
    "import 'dart:io' as io;\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod Future<bool> exists(Ref ref, io.Directory folder) async => folder.existsSync();",
    rejected: true,
  );
  ruleCase(
    'ARCH007',
    'reject synchronous IO through cascade receiver',
    "import 'dart:io';\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod File write(Ref ref) => File('sample')..writeAsStringSync('text');",
    rejected: true,
  );
  ruleCase(
    'ARCH007',
    'reject synchronous IO in annotated notifier build',
    "import 'dart:io';\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod class Tasks extends _\$Tasks { bool build() => File('sample').existsSync(); }",
    rejected: true,
  );
  ruleCase(
    'ARCH007',
    'allow asynchronous provider IO',
    "import 'dart:io';\nimport 'package:riverpod_annotation/riverpod_annotation.dart';\n@riverpod Future<bool> exists(Ref ref) async => await File('sample').exists();",
    rejected: false,
  );
  ruleCase(
    'ARCH007',
    'do not mistake unrelated Sync methods for IO',
    'class TasksPage extends StatelessWidget { Widget build(BuildContext context) { final item = repository.readSync(); return Text(item); } }',
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH007',
    'shadowed File parameter does not turn local unrelated method into IO',
    "import 'dart:io';\nclass Fake { bool existsSync() => true; }\nclass TasksPage extends StatelessWidget { Widget build(BuildContext context, File file) { if (true) { final file = Fake(); file.existsSync(); } return Text('ok'); } }",
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH007',
    'do not interpret event callback as build execution',
    "import 'dart:io';\nclass TasksPage extends StatelessWidget { Widget build(BuildContext context) => Button(onPressed: () { File('sample').existsSync(); }); }",
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/screens/tasks_page.dart',
  );
  ruleCase(
    'ARCH008',
    'reject data importing presentation',
    "import 'package:demo/features/tasks/presentation/providers/tasks.dart';",
    rejected: true,
    path: 'apps/demo/lib/features/tasks/data/task_repository.dart',
  );
  ruleCase(
    'ARCH008',
    'allow data importing domain',
    "import 'package:demo/features/tasks/domain/task.dart';",
    rejected: false,
    path: 'apps/demo/lib/features/tasks/data/task_repository.dart',
  );
  test('Exceptions are exact, justified, and stale exceptions fail', () {
    final f = Fixture();
    try {
      const issue = ArchitectureIssue(
        'ARCH004',
        'apps/demo/lib/features/task/task.dart',
        3,
        'count',
        'wrong place',
      );
      final file = File('${f.root.path}/exceptions.json');
      final entry = {
        'rule': issue.rule,
        'path': issue.path,
        'line': issue.line,
        'target': issue.target,
        'reason': 'Temporary migration fixture with explicit ownership.',
      };
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'exceptions': [entry],
        }),
      );
      expect(
        applyExceptions([issue], file).isEmpty,
        'Exact exception must apply',
      );
      expect(
        applyExceptions([], file).single.rule == 'ARCH_EXCEPTION',
        'Stale exception must fail',
      );
      entry['path'] = 'apps/*';
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'exceptions': [entry],
        }),
      );
      var rejected = false;
      try {
        applyExceptions([issue], file);
      } on FormatException {
        rejected = true;
      }
      expect(rejected, 'Wildcard exceptions must fail');
    } finally {
      f.dispose();
    }
  });
  stdout.writeln('$_passed architecture tests passed.');
}
