import 'dart:io';

import '../architecture/checker.dart';

/// Check the installed recipe, which is intentionally absent from minimal apps.
void main() {
  final source = Directory.current;
  final embedded = Directory('${source.path}/.blueprint/reference');
  final templates = embedded.existsSync() ? embedded : source;
  for (final template in ['starter_app', 'workbench_app']) {
    final fixture = Directory.systemTemp.createTempSync('diagnostics-recipe-');
    try {
      final appRoot = Directory('${fixture.path}/apps/probe');
      void copy(File file, String relative) {
        final target = File('${appRoot.path}/$relative');
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(
          file.readAsStringSync().replaceAll('__APP_PACKAGE__', 'probe'),
        );
      }

      copy(
        File(
          '${templates.path}/examples/$template/lib/core/diagnostics/app_diagnostics.dart',
        ),
        'lib/core/diagnostics/app_diagnostics.dart',
      );
      final recipe = Directory(
        '${source.path}/tool/capabilities/recipes/diagnostics/lib',
      );
      for (final file in recipe.listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.dart')) {
          copy(file, 'lib/${file.path.substring(recipe.path.length + 1)}');
        }
      }
      final issues = checkWorkspace(fixture, [
        WorkspaceMember(
          name: 'probe',
          path: 'apps/probe',
          dependencies: {
            'flutter',
            'flutter_riverpod',
            'koi_core',
            'riverpod_annotation',
            'path_provider',
            'web',
          },
        ),
      ]);
      if (issues.isNotEmpty) {
        throw StateError('$template installed recipe: ${issues.join('\n')}');
      }
      stdout.writeln('PASS $template installed diagnostics architecture');
    } finally {
      fixture.deleteSync(recursive: true);
    }
  }
}
