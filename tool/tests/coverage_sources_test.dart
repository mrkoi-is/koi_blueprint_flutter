import 'dart:io';

Future<void> main() async {
  final temporary = Directory.systemTemp.createTempSync('coverage-members-');
  try {
    final member = Directory('${temporary.path}/examples/demo');
    void write(String relative, String source) {
      final file = File('${member.path}/$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(source);
    }

    write('lib/own.dart', 'int value() => 1;');
    write('modules/child/lib/child.dart', 'int childValue() => 2;');
    final report = File('${temporary.path}/lcov.info')
      ..writeAsStringSync('SF:lib/own.dart\nDA:1,1\nend_of_record\n');
    Future<ProcessResult> check() => Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/check_coverage_sources.dart',
      member.path,
      report.path,
    ]);
    final covered = await check();
    if (covered.exitCode != 0) {
      throw StateError(
        'Nested member must not contaminate parent: ${covered.stderr}',
      );
    }
    report.writeAsStringSync('SF:lib\\own.dart\nDA:1,1\nend_of_record\n');
    final windowsPaths = await check();
    if (windowsPaths.exitCode != 0) {
      throw StateError(
        'LCOV Windows separators must normalize: ${windowsPaths.stderr}',
      );
    }
    write('lib/missing.dart', 'int missing() => 3;');
    final missing = await check();
    if (missing.exitCode == 0 ||
        !(missing.stderr as String).contains('lib/missing.dart')) {
      throw StateError('Missing executable source must still fail');
    }
    stdout.writeln('3 coverage-source regression cases passed.');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
