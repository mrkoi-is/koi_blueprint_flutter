import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// VM LCOV cannot execute browser interop. Keep those executable lines in the
/// denominator with ZERO hits; browser behavior has its own mandatory tests.
/// Other missing sources still fail check_coverage_sources.dart.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError('include_browser_coverage <member> <lcov.info>');
  }
  final member = Directory(arguments[0]);
  final report = File(arguments[1]);
  final contents = report.readAsStringSync();
  final included = contents
      .split('\n')
      .where((line) => line.startsWith('SF:'))
      .map((line) => line.substring(3).replaceAll(r'\', '/'))
      .toSet();
  final additions = StringBuffer();
  final lib = Directory('${member.path}/lib');
  if (!lib.existsSync()) return;
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) continue;
    final source = file.readAsStringSync();
    // This is platform classification, not a coverage exclusion.
    if (!RegExp(
      r'''import\s+['"](?:dart:js_interop|package:web/[^'"]+|package:drift/wasm\.dart)['"]''',
    ).hasMatch(source)) {
      continue;
    }
    final relative = file.path
        .substring(member.path.length + 1)
        .replaceAll(r'\', '/');
    if (included.contains(relative)) continue;
    final parsed = parseString(
      content: source,
      featureSet: FeatureSet.latestLanguageVersion(),
    );
    final visitor = _Lines(parsed.lineInfo);
    parsed.unit.accept(visitor);
    if (visitor.lines.isEmpty) continue;
    final lines = visitor.lines.toList()..sort();
    additions.writeln('SF:$relative');
    for (final line in lines) {
      additions.writeln('DA:$line,0');
    }
    additions.writeln('LF:${lines.length}');
    additions.writeln('LH:0');
    additions.writeln('end_of_record');
    stdout.writeln(
      'Unmeasured browser lines counted as uncovered: $relative (${lines.length})',
    );
  }
  if (additions.isNotEmpty) report.writeAsStringSync('$contents\n$additions');
}

final class _Lines extends RecursiveAstVisitor<void> {
  _Lines(this.info);
  final LineInfo info;
  final Set<int> lines = {};
  void add(AstNode node) => lines.add(info.getLocation(node.offset).lineNumber);
  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    add(node.expression);
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitBlock(Block node) {
    for (final statement in node.statements) {
      add(statement);
    }
    super.visitBlock(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    for (final initializer in node.initializers) {
      add(initializer);
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final parent = node.parent;
    if (node.initializer != null &&
        parent is VariableDeclarationList &&
        !parent.isConst) {
      add(node.initializer!);
    }
    super.visitVariableDeclaration(node);
  }
}
