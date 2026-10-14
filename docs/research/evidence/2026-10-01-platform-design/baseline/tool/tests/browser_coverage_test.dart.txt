import 'dart:io';

Future<void> main() async {
  final temporary = Directory.systemTemp.createTempSync(
    'browser-coverage-test-',
  );
  try {
    final member = Directory('${temporary.path}/example')..createSync();
    final lib = Directory('${member.path}/lib')..createSync();
    File('${lib.path}/browser.dart')
        .writeAsStringSync("import 'dart:js_interop';\nint pending() => 1;\n");
    File('${lib.path}/web_only.dart').writeAsStringSync(
      "import 'package:web/web.dart';\nvoid release() => URL.revokeObjectURL('blob:x');\n",
    );
    File('${lib.path}/native.dart').writeAsStringSync('int value() => 2;\n');
    final report = File('${temporary.path}/lcov.info')
      ..writeAsStringSync('SF:lib/native.dart\nDA:1,3\nend_of_record\n');
    Future<void> include() async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/include_browser_coverage.dart',
        member.path,
        report.path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('${result.stdout}${result.stderr}');
      }
    }

    await include();
    final first = report.readAsStringSync();
    if (!first.contains('SF:lib/browser.dart\nDA:2,0') ||
        !first.contains('SF:lib/web_only.dart\nDA:2,0') ||
        !first.contains('DA:1,3')) {
      throw StateError(
        'Browser source must count as uncovered without altering measured hits: $first',
      );
    }
    await include();
    if (report.readAsStringSync() != first) {
      throw StateError('Coverage augmentation must be idempotent');
    }
    File('${lib.path}/missing.dart')
        .writeAsStringSync('int untested() => 0;\n');
    final check = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/check_coverage_sources.dart',
      member.path,
      report.path,
    ]);
    if (check.exitCode == 0 ||
        !(check.stderr as String).contains('lib/missing.dart')) {
      throw StateError('Missing ordinary sources must still fail');
    }
    stdout.writeln(
      'Browser coverage: zero hits, idempotence and ordinary-source protection passed.',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
