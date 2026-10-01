import 'dart:convert';
import 'dart:io';

import 'architecture/checker.dart';

Future<void> main(List<String> arguments) async {
  var rootPath = Directory.current.path;
  String? exceptionsPath;
  var json = false;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--root':
        if (++i >= arguments.length) {
          stderr.writeln('--root requires a path');
          exitCode = 2;
          return;
        }
        rootPath = arguments[i];
      case '--exceptions':
        if (++i >= arguments.length) {
          stderr.writeln('--exceptions requires a path');
          exitCode = 2;
          return;
        }
        exceptionsPath = arguments[i];
      case '--json':
        json = true;
      default:
        stderr.writeln(
          'Usage: dart run tool/check_architecture.dart [--root path] [--exceptions file] [--json]',
        );
        exitCode = 2;
        return;
    }
  }
  try {
    final root = Directory(Directory(rootPath).resolveSymbolicLinksSync());
    final members = await discoverMembers(root);
    final issues = applyExceptions(
      checkWorkspace(root, members),
      File(exceptionsPath ?? '${root.path}/tool/architecture_exceptions.json'),
    );
    if (json) {
      stdout.writeln(
        jsonEncode({
          'ok': issues.isEmpty,
          'issues': [for (final issue in issues) issue.toJson()],
        }),
      );
    } else if (issues.isEmpty) {
      stdout.writeln(
        'Architecture checks passed (${members.length - 1} workspace members).',
      );
    } else {
      for (final issue in issues) {
        stderr.writeln(issue);
      }
    }
    if (issues.isNotEmpty) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Architecture checker failed: $error');
    exitCode = 2;
  }
}
