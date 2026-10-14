import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

const _compileOnlySources = <String>{
  'packages/koi_api_bootstrap/lib/src/backend/web_backend.dart',
  'packages/koi_api_bootstrap/lib/src/token_storage/web_token_session.dart',
};

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      '用法: dart run tool/check_coverage_sources.dart <member> <lcov.info>',
    );
    exitCode = 2;
    return;
  }

  final memberPath = Directory(arguments[0]).path
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  final report = File(arguments[1]);
  final coveredSources = report
      .readAsLinesSync()
      .where((line) => line.startsWith('SF:'))
      .map((line) => line.substring(3).replaceAll(r'\', '/'))
      .toSet();
  final missingExecutableSources = <String>[];

  // A workspace member owns only its lib; nested members have their own reports.
  final library = Directory('$memberPath/lib');
  if (!library.existsSync()) return;
  for (final entity in library.listSync(recursive: true)) {
    if (entity is! File ||
        !entity.path.endsWith('.dart') ||
        entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart')) {
      continue;
    }

    final relativeSource = entity.path
        .replaceAll(r'\', '/')
        .substring(memberPath.length + 1);
    // Match blueprint.coverage's generated-directory boundary. A generated
    // export may live outside this directory, but contains no executable body.
    if (relativeSource.split('/').contains('generated')) continue;
    if (coveredSources.contains(relativeSource)) {
      continue;
    }

    final repositorySource = '$memberPath/$relativeSource';
    if (_compileOnlySources.contains(repositorySource) ||
        (relativeSource == 'lib/main.dart' &&
            (repositorySource.startsWith('apps/') ||
                repositorySource.startsWith('examples/')))) {
      continue;
    }

    final visitor = _ExecutableCodeVisitor();
    parseFile(
      path: entity.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit.accept(visitor);
    if (visitor.hasExecutableCode) {
      missingExecutableSources.add(repositorySource);
    }
  }

  if (missingExecutableSources.isEmpty) {
    return;
  }

  stderr.writeln('以下含可执行逻辑的手写源码未进入覆盖率报告：');
  for (final source in missingExecutableSources..sort()) {
    stderr.writeln('  $source');
  }
  exitCode = 1;
}

final class _ExecutableCodeVisitor extends RecursiveAstVisitor<void> {
  bool hasExecutableCode = false;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if (node.block.statements.isNotEmpty) {
      hasExecutableCode = true;
    }
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    hasExecutableCode = true;
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.initializers.isNotEmpty) {
      hasExecutableCode = true;
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final declarationList = node.parent;
    if (node.initializer != null &&
        declarationList is VariableDeclarationList &&
        !declarationList.isConst) {
      hasExecutableCode = true;
    }
    super.visitVariableDeclaration(node);
  }
}
