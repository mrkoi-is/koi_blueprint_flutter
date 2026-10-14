import 'dart:convert';
import 'dart:io';

import '../architecture/checker.dart';

int _passed = 0;

void expect(Object? condition, String message) {
  if (condition != true) throw StateError(message);
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

void mountedCase(String description, String body, {required bool rejected}) {
  ruleCase('ARCH014', description, '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class Tasks extends _\$Tasks {
  int build() => 0;
  Future<void> refresh() async {
    $body
  }
}
''', rejected: rejected);
}

void main() {
  test('Windows workspace root identity ignores drive and directory case', () {
    expect(
      relativePathWithin(
            r'D:\a\_temp\koi-blueprint-generated',
            r'd:\A\_TEMP\koi-blueprint-generated\',
            windows: true,
          ) ==
          '.',
      'Pub may spell the same Windows root with a lowercase drive',
    );
  });
  test(
    'Windows children preserve relative spelling and normalize separators',
    () {
      expect(
        relativePathWithin(
              r'D:\a\_temp\workspace',
              'd:/A/_temp/WORKSPACE/apps/Demo/lib/../lib/Feature.dart',
              windows: true,
            ) ==
            'apps/Demo/lib/Feature.dart',
        'Containment must not lowercase the reported member or source path',
      );
      expect(
        relativePathWithin(r'D:\', r'd:\Apps\Demo', windows: true) ==
            'Apps/Demo',
        'Drive roots are valid workspace roots',
      );
    },
  );
  test(
    'Windows containment rejects adjacent roots, traversal and other drives',
    () {
      for (final outside in [
        r'd:\a\workspace-other\apps\demo',
        r'd:\a\workspace\..\outside',
        r'e:\a\workspace\apps\demo',
      ]) {
        expect(
          relativePathWithin(r'D:\a\workspace', outside, windows: true) == null,
          'Expected path outside workspace: $outside',
        );
      }
    },
  );
  test('Windows UNC containment observes the share boundary', () {
    expect(
      relativePathWithin(
            r'\\Server\Share\Workspace',
            r'\\server\share\WORKSPACE\Apps\Demo',
            windows: true,
          ) ==
          'Apps/Demo',
      'UNC server and share casing should not change identity',
    );
    expect(
      relativePathWithin(
            r'\\Server\Share\Workspace',
            r'\\server\other\workspace\Apps\Demo',
            windows: true,
          ) ==
          null,
      'Another UNC share is outside the workspace',
    );
  });
  test(
    'POSIX containment retains case sensitivity and supports filesystem root',
    () {
      expect(
        relativePathWithin(
              '/Work/Repo',
              '/work/Repo/lib/a.dart',
              windows: false,
            ) ==
            null,
        'Windows case folding must not apply to POSIX paths',
      );
      expect(
        relativePathWithin('/', '/Apps/Demo', windows: false) == 'Apps/Demo',
        'Filesystem root must contain its descendants',
      );
      expect(
        relativePathWithin('/', '/', windows: false) == '.',
        'Filesystem root must equal itself',
      );
    },
  );
  test('Dart CLI exit codes and JSON contract', () {
    final fixture = Fixture();
    try {
      fixture.source(
        'pubspec.yaml',
        'name: fixture\nenvironment:\n  sdk: ^3.13.0\nworkspace:\n  - apps/demo\n',
      );
      fixture.source(
        'apps/demo/pubspec.yaml',
        'name: demo\nresolution: workspace\nenvironment:\n  sdk: ^3.13.0\n',
      );
      const page = 'apps/demo/lib/features/tasks/presentation/page.dart';
      fixture.source(
        page,
        'class Page extends StatelessWidget { final VoidCallback a,b,c,d,e; }',
      );
      ProcessResult run() => Process.runSync(Platform.resolvedExecutable, [
        File('tool/check_architecture.dart').absolute.path,
        '--root',
        fixture.root.path,
        '--json',
      ]);
      final warning = run();
      expect(
        warning.exitCode == 0,
        'Warning-only CLI passes: ${warning.stderr}',
      );
      final data = jsonDecode(warning.stdout as String) as Map<String, dynamic>;
      expect(data['ok'] == true, 'Warnings do not affect ok');
      expect(data['summary']['warnings'] == 1, 'Warning count retained');
      fixture.source(
        'apps/demo/lib/features/tasks/domain/model.dart',
        "import 'dart:io';",
      );
      final mixed = run();
      expect(mixed.exitCode == 1, 'Structural errors exit 1: ${mixed.stderr}');
      final errors = jsonDecode(mixed.stdout as String) as Map<String, dynamic>;
      expect(
        errors['summary']['errors'] == 1 && errors['summary']['warnings'] == 1,
        'Mixed counts',
      );
      fixture.source(
        'tool/architecture_exceptions.json',
        '{"version": 1, "exceptions": [{"invalid": true}]}',
      );
      expect(run().exitCode == 2, 'Invalid configuration exits 2');
    } finally {
      fixture.dispose();
    }
  });

  test('Severity controls the report, preserving count observations', () {
    final f = Fixture();
    try {
      f
        ..member('demo', 'apps/demo')
        ..source(
          'apps/demo/lib/features/tasks/presentation/page.dart',
          'class Page extends StatelessWidget { final VoidCallback a,b,c,d,e; }',
        );
      final warning = f.check().single;
      expect(
        warning.severity == ArchitectureSeverity.warning,
        'Counts are warnings',
      );
      expect(warning.measure == 5, 'Count remains available');
      expect(
        architectureReport([warning])['ok'] == true,
        'Warning does not fail',
      );
      final hard = ArchitectureIssue(
        'ARCH003',
        'domain.dart',
        1,
        'flutter',
        'Domain violation',
      );
      final mixed = architectureReport([warning, hard]);
      expect(mixed['ok'] == false, 'Error fails');
      expect(
        jsonEncode(mixed).contains('"severity":"warning"'),
        'JSON has severity',
      );
      expect(
        jsonEncode(mixed).contains('"errors":1,"warnings":1'),
        'Summary counts both',
      );
      final file = File('${f.root.path}/exceptions.json');
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'exceptions': [
            {
              'rule': 'ARCH012',
              'path': 'apps/demo/lib/probe.dart',
              'line': 1,
              'target': 'frame_rate.split',
              'reason': 'Legacy product parser kept pending migration.',
            },
          ],
        }),
      );
      expect(
        applyExceptions([], file).single.severity ==
            ArchitectureSeverity.warning,
        'Retired exception is a warning',
      );
    } finally {
      f.dispose();
    }
  });

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
      f
        ..member('koi_ui', 'packages/koi_ui', dependencies: {'widget_helpers'})
        ..member(
          'widget_helpers',
          'packages/widget_helpers',
          dependencies: {'flutter'},
        )
        ..source(
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
      f
        ..member('alpha', 'examples/demo/modules/alpha', dependencies: {'beta'})
        ..member('beta', 'examples/demo/modules/beta');
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
        f
          ..member('alpha', source, dependencies: {'demo'})
          ..member('demo', 'apps/demo');
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
        f
          ..member('demo', 'apps/demo', dependencies: {'alpha', 'contracts'})
          ..member('alpha', 'modules/alpha', dependencies: {'contracts'})
          ..member('contracts', 'packages/contracts');
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
      f
        ..member('demo', 'apps/demo', dependencies: {'flutter', 'riverpod'})
        ..source(
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
        f
          ..member(
            'koi_domain',
            'packages/koi_domain',
            dependencies: {'bridge'},
          )
          ..member('bridge', 'packages/bridge', dependencies: {'flutter'});
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
  ruleCase(
    'ARCH010',
    'reject a presentation state that owns the editable draft',
    '''
class Page extends StatefulWidget {
  const Page({super.key});
  State<Page> createState() => _PageState();
}
class _PageState extends State<Page> {
  String? a; String? b; String? c; String? d;
  int? e; int? f; int? g; int? h; bool i = false;
  Widget build(BuildContext context) => const SizedBox();
}
''',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH010',
    'allow a presentation state that keeps view chrome',
    '''
class Page extends StatefulWidget {
  const Page({super.key});
  State<Page> createState() => _PageState();
}
class _PageState extends State<Page> {
  bool overlay = true;
  double position = 0;
  Widget build(BuildContext context) => const SizedBox();
}
''',
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH011',
    'reject a page that drills command callbacks',
    '''
class Page extends StatelessWidget {
  const Page({required this.onSave, required this.onFavorite, required this.onTags, required this.onUse, required this.onPreview, super.key});
  final void Function() onSave;
  final void Function() onFavorite;
  final void Function() onTags;
  final void Function() onUse;
  final VoidCallback onPreview;
  Widget build(BuildContext context) => const SizedBox();
}
''',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH011',
    'reject ValueChanged callbacks that hide a function type',
    '''
class Page extends StatelessWidget {
  const Page({required this.onCancel, required this.onRetry, required this.onOpen, required this.onClose, required this.onSave, super.key});
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onSave;
  Widget build(BuildContext context) => const SizedBox();
}
''',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH011',
    'allow a page with a few command callbacks',
    '''
class Page extends StatelessWidget {
  const Page({required this.onSave, required this.onClose, super.key});
  final void Function() onSave;
  final VoidCallback onClose;
  Widget build(BuildContext context) => const SizedBox();
}
''',
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH012',
    'retired media rule is not emitted',
    r'''
double rate(Map stream) {
  final parts = '${stream['avg_frame_rate']}'.split('/');
  return 0;
}
''',
    rejected: false,
    path: 'apps/demo/lib/shell/import.dart',
  );
  ruleCase(
    'ARCH012',
    'allow a shared parser outside apps',
    r'''
double? rate(Map stream) {
  final parts = '${stream['avg_frame_rate']}'.split('/');
  return null;
}
''',
    rejected: false,
    path: 'packages/koi_media/lib/src/frame_rate.dart',
    setup: (f) => f.member('koi_media', 'packages/koi_media'),
  );
  ruleCase(
    'ARCH013',
    'reject a shell coordinator importing presentation',
    "import 'package:demo/features/tasks/presentation/page.dart';",
    rejected: true,
    path: 'apps/demo/lib/shell/coordinators/storage.dart',
  );
  ruleCase(
    'ARCH013',
    'allow the shell to compose a feature page',
    "import 'package:demo/features/tasks/presentation/page.dart';",
    rejected: false,
    path: 'apps/demo/lib/shell/app_shell.dart',
  );
  ruleCase(
    'ARCH013',
    'allow a coordinator to import application',
    "import 'package:demo/features/tasks/application/media.dart';",
    rejected: false,
    path: 'apps/demo/lib/shell/coordinators/storage.dart',
  );
  test('ARCH010 reports a field measure and a budget stops growth', () {
    final fixture = Fixture();
    try {
      fixture
        ..member('demo', 'apps/demo')
        ..source('apps/demo/lib/features/tasks/presentation/page.dart', '''
class Page extends StatefulWidget {
  const Page({super.key});
  State<Page> createState() => _PageState();
}
class _PageState extends State<Page> {
  String? a; String? b; String? c; String? d;
  int? e; int? f; int? g; int? h; bool i = false;
  Widget build(BuildContext context) => const SizedBox();
}
''');
      final issue = fixture.check().singleWhere(
        (item) => item.rule == 'ARCH010',
      );
      expect(
        issue.measure == 9,
        'ARCH010 measure must count fields, got ${issue.measure}',
      );
      final file = File('${fixture.root.path}/exceptions.json');
      final entry = {
        'rule': 'ARCH010',
        'path': issue.path,
        'line': issue.line,
        'target': issue.target,
        'reason': 'View chrome stays under the recorded field budget.',
        'budget': 9,
      };
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'exceptions': [entry],
        }),
      );
      expect(
        applyExceptions([issue], file).isEmpty,
        'Budget that fits must suppress',
      );
      entry['budget'] = 8;
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'exceptions': [entry],
        }),
      );
      final exceeded = applyExceptions([issue], file);
      expect(
        exceeded.length == 2,
        'Exceeded budget keeps the issue and adds ARCH_EXCEPTION',
      );
      expect(
        exceeded.any((item) => item.rule == 'ARCH_EXCEPTION'),
        'Exceeded budget must fail the check',
      );
      entry.remove('budget');
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
      expect(rejected, 'ARCH010 exception without a budget must fail');
      file.writeAsStringSync(
        jsonEncode({'version': 1, 'exceptions': <Object>[]}),
      );
      expect(
        applyExceptions([issue], file).length == 1,
        'Empty exceptions keep the issue',
      );
    } finally {
      fixture.dispose();
    }
  });
  ruleCase(
    'ARCH010',
    'count each instance variable in one declaration',
    'class S extends State<Page> { int a=0,b=0,c=0,d=0,e=0,f=0,g=0,h=0,i=0; }',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH010',
    'ignore static constants in State budget',
    'class S extends State<Page> { static int a=0,b=0,c=0,d=0,e=0,f=0,g=0,h=0,i=0; int position=0; }',
    rejected: false,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH011',
    'constructor cannot hide commands in an object',
    'class Page extends StatelessWidget { Page({required VoidCallback a, required VoidCallback b, required VoidCallback c, required VoidCallback d, required VoidCallback e}); final Object commands=null; }',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH011',
    'recognize local function typedefs',
    'typedef Action = void Function(); class Page extends StatelessWidget { final Action a,b,c,d,e; }',
    rejected: true,
    path: 'apps/demo/lib/features/tasks/presentation/page.dart',
  );
  ruleCase(
    'ARCH013',
    'reject chained shared exports and terminate cycles',
    "import 'package:demo/shared/first.dart';",
    rejected: true,
    path: 'apps/demo/lib/shell/coordinators/storage.dart',
    setup: (f) {
      f
        ..source('apps/demo/lib/shared/first.dart', "export 'second.dart';")
        ..source(
          'apps/demo/lib/shared/second.dart',
          "export 'first.dart'; export '../features/tasks/presentation/page.dart';",
        );
    },
  );
  ruleCase(
    'ARCH006',
    'reject feature-root widget importing data layer without presentation folder',
    "import 'package:demo/features/tasks/data/task_repository.dart'; class MainShellScreen extends StatelessWidget {}",
    rejected: true,
    path: 'apps/demo/lib/features/main_shell/main_shell_screen.dart',
  );
  ruleCase(
    'ARCH010',
    'reject feature-root State exceeding field budget without presentation folder',
    'class S extends State<Page> { int a=0,b=0,c=0,d=0,e=0,f=0,g=0,h=0,i=0; }',
    rejected: true,
    path: 'apps/demo/lib/features/main_shell/main_shell_screen.dart',
  );
  ruleCase(
    'ARCH011',
    'reject feature-root Widget exceeding callback budget without presentation folder',
    'class MainShellScreen extends StatelessWidget { final VoidCallback a,b,c,d,e; }',
    rejected: true,
    path: 'apps/demo/lib/features/main_shell/main_shell_screen.dart',
  );
  ruleCase(
    'ARCH014',
    'reject async notifier assigning state after await without ref.mounted',
    '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class Tasks extends _\$Tasks {
  int build() => 0;
  Future<void> refresh() async {
    final next = await Future.value(1);
    state = next;
  }
}
''',
    rejected: true,
  );
  ruleCase(
    'ARCH014',
    'reject async notifier checking ref.mounted only before await',
    '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class Tasks extends _\$Tasks {
  int build() => 0;
  Future<void> refresh() async {
    if (!ref.mounted) return;
    final next = await Future.value(1);
    state = next;
  }
}
''',
    rejected: true,
  );
  ruleCase('ARCH014', 'allow async notifier checking ref.mounted after await before state assignment', '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class Tasks extends _\$Tasks {
  int build() => 0;
  Future<void> refresh() async {
    state = 0;
    final next = await Future.value(1);
    if (!ref.mounted) return;
    state = next;
  }
}
''', rejected: false);
  mountedCase(
    'reject a state assignment whose right hand side suspends',
    'state = await Future.value(1);',
    rejected: true,
  );
  mountedCase(
    'reject RHS await even inside a previously mounted branch',
    'if (ref.mounted) state = await Future.value(1);',
    rejected: true,
  );
  mountedCase(
    'reject mounted check after the state write',
    'await Future.value(1); state = 1; if (!ref.mounted) return;',
    rejected: true,
  );
  mountedCase('reject a guard invalidated by a second suspension', '''
await Future.value(1);
if (!ref.mounted) return;
await Future.value(2);
state = 2;
''', rejected: true);
  mountedCase('allow a fresh guard after each suspension', '''
await Future.value(1);
if (!ref.mounted) return;
state = 1;
await Future.value(2);
if (!ref.mounted) return;
state = 2;
''', rejected: false);
  for (final declaration in [
    'final guard = () => ref.mounted;',
    'final guard = () { if (!ref.mounted) return; };',
    'final guard = () async { if (!ref.mounted) return; };',
    'bool guard() => ref.mounted;',
    'final mounted = ref.mounted;',
  ]) {
    mountedCase(
      'reject a read or uninvoked closure as a mounted guard: $declaration',
      'await Future.value(1); $declaration state = 1;',
      rejected: true,
    );
  }
  mountedCase(
    'closure declarations do not introduce a suspension in the outer method',
    'final work = () async { await Future.value(1); }; state = 1;',
    rejected: false,
  );
  mountedCase(
    'allow a write only on the mounted branch',
    'await Future.value(1); if (ref.mounted) { state = 1; }',
    rejected: false,
  );
  mountedCase(
    'allow compound early exit for mounted and operation identity',
    'await Future.value(1); if (!ref.mounted || stale) return; state = 1;',
    rejected: false,
  );
  mountedCase(
    'allow a compound positive guard',
    'await Future.value(1); if (ref.mounted && !stale) state = 1;',
    rejected: false,
  );
  mountedCase(
    'reject a positive OR guard that can succeed without mounted',
    'await Future.value(1); if (ref.mounted || override) state = 1;',
    rejected: true,
  );
  mountedCase(
    'reject a negative AND early exit that can retain an unmounted path',
    'await Future.value(1); if (!ref.mounted && stale) return; state = 1;',
    rejected: true,
  );
  mountedCase(
    'reject a guard on only one unrelated branch',
    'await Future.value(1); if (enabled) { if (!ref.mounted) return; } state = 1;',
    rejected: true,
  );
  mountedCase(
    'allow the else branch of an unmounted return',
    'await Future.value(1); if (!ref.mounted) return; else state = 1;',
    rejected: false,
  );
  mountedCase(
    'allow a parenthesized guard and explicit this receiver',
    'await Future.value(1); if (!(this.ref.mounted)) return; this.state = 1;',
    rejected: false,
  );
  mountedCase(
    'reject suspension during a compound condition after its mounted check',
    'await Future.value(1); if (ref.mounted && await ready()) state = 1;',
    rejected: true,
  );
  mountedCase(
    'allow mounted checked after suspension within a compound condition',
    'if (await ready() && ref.mounted) state = 1;',
    rejected: false,
  );
  mountedCase(
    'allow guarded conditional expression writes',
    'await Future.value(1); ref.mounted ? state = 1 : null;',
    rejected: false,
  );
  mountedCase('allow mounted checks in both try and catch', '''
try {
  await Future.value(1);
  if (!ref.mounted) return;
  state = 1;
} catch (error) {
  if (ref.mounted) state = 0;
}
''', rejected: false);
  mountedCase(
    'reject a catch write guarded only on the successful try path',
    '''
try {
  await Future.value(1);
  if (!ref.mounted) return;
  state = 1;
} catch (error) {
  state = 0;
}
''',
    rejected: true,
  );
  mountedCase(
    'allow a mounted guard in finally',
    'try { await Future.value(1); } finally { if (ref.mounted) state = 1; }',
    rejected: false,
  );
  mountedCase('reject finally reached by the unmounted early return', '''
try {
  await Future.value(1);
  if (!ref.mounted) return;
} finally {
  state = 0;
}
''', rejected: true);
  mountedCase('allow a guard after try catch joins', '''
try { await Future.value(1); } catch (error) { log(error); }
if (!ref.mounted) return;
state = 1;
''', rejected: false);
  mountedCase('preserve a successful guard through synchronous finally', '''
try {
  await Future.value(1);
  if (!ref.mounted) return;
} finally { cleanup(); }
state = 1;
''', rejected: false);
  mountedCase('invalidate a try guard when finally suspends', '''
try {
  await Future.value(1);
  if (!ref.mounted) return;
} finally { await cleanup(); }
state = 1;
''', rejected: true);
  mountedCase(
    'reject a mounted pattern matching the false value',
    'await Future.value(1); if (ref.mounted case false) state = 1;',
    rejected: true,
  );
  mountedCase('reject a guard belonging to another switch branch', '''
await Future.value(1);
switch (choice) {
  case 1:
    if (!ref.mounted) return;
    break;
  default:
    state = 1;
}
''', rejected: true);
  mountedCase(
    'allow an explicit guard in the switch branch that writes state',
    '''
await Future.value(1);
switch (choice) {
  case 1:
    if (!ref.mounted) return;
    state = 1;
    break;
  default:
    break;
}
''',
    rejected: false,
  );
  mountedCase(
    'reject a loop write after an unguarded suspension',
    'while (ready) { await next(); state = 1; }',
    rejected: true,
  );
  mountedCase(
    'allow an explicit guard following a suspension inside a loop',
    'while (ready) { await next(); if (!ref.mounted) return; state = 1; }',
    rejected: false,
  );
  mountedCase(
    'reject async for writes without a per-iteration guard',
    'await for (final item in items) { state = item; }',
    rejected: true,
  );
  mountedCase(
    'allow an explicit guard in an async for loop',
    'await for (final item in items) { if (!ref.mounted) return; state = item; }',
    rejected: false,
  );
  mountedCase(
    'allow a guard before every potentially throwing try operation',
    '''
await Future.value(1);
try {
  if (!ref.mounted) return;
  state = 1;
} catch (error) {
  state = 0;
}
''',
    rejected: false,
  );
  mountedCase('reject a suspension in an if case when clause', '''
await Future.value(1);
if (ref.mounted case true when await ready()) { state = 1; }
''', rejected: true);
  mountedCase(
    'reject a when suspension even with no earlier await',
    'if (value case final item when await ready()) { state = 1; }',
    rejected: true,
  );
  for (final operation in [
    'value as String',
    'value!',
    '1 ~/ zero',
    'left + right',
    'left == right',
    '~value',
    '-value',
    '++value',
    'value++',
  ]) {
    mountedCase(
      'reject a catch write when $operation can throw before the guard',
      '''
await Future.value(1);
try {
  final result = $operation;
  if (!ref.mounted) return;
  state = 1;
} catch (error) {
  state = 0;
}
''',
      rejected: true,
    );
    mountedCase(
      'allow a catch write when $operation executes after the guard',
      '''
await Future.value(1);
try {
  if (!ref.mounted) return;
  final result = $operation;
  state = 1;
} catch (error) {
  state = 0;
}
''',
      rejected: false,
    );
  }
  mountedCase('preserve short circuit mounted facts before a possibly throwing comparison', '''
await Future.value(1);
try {
  if (!ref.mounted || operation != currentOperation) return;
  state = 1;
} catch (error) {
  state = 0;
}
''', rejected: false);
  stdout.writeln('$_passed architecture tests passed.');
}
