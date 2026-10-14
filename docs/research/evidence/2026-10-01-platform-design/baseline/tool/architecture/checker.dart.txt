import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:yaml/yaml.dart';

/// These rules deliberately check structural facts, not business semantics.
const architectureRules = <String, String>{
  'ARCH001':
      'Enforce shared package, application and business module directions.',
  'ARCH002': 'Business modules are consumed through their public entrypoint.',
  'ARCH003': 'Domain/foundational packages stay pure Dart; koi_ui stays presentation-only.',
  'ARCH004': 'Feature providers belong in presentation/providers.',
  'ARCH005': 'Use annotated Riverpod declarations, not handwritten providers.',
  'ARCH006':
      'Screens/widgets must not import IO, network clients, or data layers.',
  'ARCH007':
      'Widget build and synchronous provider build paths must not do sync IO.',
  'ARCH008': 'Data/application layers must not depend on presentation.',
  'ARCH009':
      'All packages under managed source roots must be Pub workspace members.',
};

String normalized(String path) => path.replaceAll('\\', '/');

String relativeTo(Directory root, String path) {
  final base = normalized(root.absolute.path).replaceFirst(RegExp(r'/$'), '');
  final absolute = normalized(File(path).absolute.path);
  if (absolute == base) return '.';
  if (!absolute.startsWith('$base/')) {
    throw FormatException('Path is outside workspace: $path');
  }
  return absolute.substring(base.length + 1);
}

final class ArchitectureIssue {
  const ArchitectureIssue(
    this.rule,
    this.path,
    this.line,
    this.target,
    this.message,
  );
  final String rule;
  final String path;
  final int line;
  final String target;
  final String message;
  Map<String, Object> toJson() => {
    'rule': rule,
    'path': path,
    'line': line,
    'target': target,
    'message': message,
  };
  @override
  String toString() => '$path:$line [$rule] $message ($target)';
}

final class WorkspaceMember {
  WorkspaceMember({
    required this.name,
    required this.path,
    required this.dependencies,
  });
  final String name;
  final String path;
  final Set<String> dependencies;
  bool get isModule => path.split('/').contains('modules');
  bool get isShared => path.split('/').contains('packages') && !isModule;
  bool get isApp => path != '.' && !isShared && !isModule;
  bool get isPure =>
      name == 'koi_core' ||
      name == 'koi_domain' ||
      name == 'koi_auth' ||
      name.endsWith('_domain');
  bool get isUi => name == 'koi_ui';
}

/// Pub, rather than a second manifest or a partial YAML workspace parser, owns
/// member discovery. YAML is only used to read each member's runtime dependencies.
Future<List<WorkspaceMember>> discoverMembers(Directory root) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'workspace',
    'list',
    '--json',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw StateError(
      'dart pub workspace list --json failed:\n${result.stderr}',
    );
  }
  final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return [
    for (final entry in data['packages'] as List<dynamic>)
      readMember(root, (entry as Map<String, dynamic>)['path'] as String),
  ];
}

WorkspaceMember readMember(Directory root, String absolutePath) {
  final manifest = loadYaml(
    File('$absolutePath/pubspec.yaml').readAsStringSync(),
  ) as YamlMap;
  final dependencies = manifest['dependencies'];
  return WorkspaceMember(
    name: manifest['name'] as String,
    path: relativeTo(root, absolutePath),
    dependencies: dependencies is YamlMap
        ? dependencies.keys.cast<String>().toSet()
        : {},
  );
}

const _impurePackages = <String>{
  'flutter',
  'flutter_riverpod',
  'riverpod',
  'riverpod_annotation',
  'get',
  'provider',
  'dio',
  'http',
  'koi_network',
  'flutter_secure_storage',
  'path_provider',
  'shared_preferences',
  'hive',
  'hive_flutter',
  'drift',
  'file_selector',
  'file_selector_platform_interface',
  'cross_file',
  'media_kit',
  'media_kit_video',
  'media_kit_libs_video',
  'web',
  'ffi',
  'js',
};
const _platformLibraries = <String>{
  'dart:io',
  'dart:ffi',
  'dart:html',
  'dart:js',
  'dart:js_util',
  'dart:js_interop',
  'dart:js_interop_unsafe',
};
const _networkPackages = <String>{'dio', 'http', 'koi_network'};

String? packageName(String uri) => uri.startsWith('package:')
    ? uri.substring('package:'.length).split('/').first
    : null;

bool _isImpurePackage(String name) =>
    _impurePackages.contains(name) ||
    name.startsWith('file_selector_') ||
    name.startsWith('media_kit_') ||
    name.startsWith('path_provider_') ||
    name.endsWith('_api') ||
    name.endsWith('_network') ||
    name == 'koi_api_bootstrap';

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

bool _badDirection(WorkspaceMember source, WorkspaceMember target) {
  if (source.name == target.name || target.path == '.') return false;
  if (source.isShared || source.isModule) return !target.isShared;
  return source.isApp && target.isApp;
}

List<ArchitectureIssue> checkWorkspace(
  Directory root,
  List<WorkspaceMember> members,
) {
  final issues = <ArchitectureIssue>[];
  final registered = members.map((member) => member.path).toSet();
  void checkMembership(Directory directory) {
    if (!directory.existsSync()) return;
    final manifest = File('${directory.path}/pubspec.yaml');
    final path = relativeTo(root, directory.path);
    if (manifest.existsSync() && !registered.contains(path)) {
      issues.add(
        ArchitectureIssue(
          'ARCH009',
          '$path/pubspec.yaml',
          1,
          path,
          'Package is absent from dart pub workspace list; register it before validation',
        ),
      );
    }
    for (final child
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      final name = child.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (name.startsWith('.') ||
          {'build', 'coverage', 'node_modules'}.contains(name)) {
        continue;
      }
      checkMembership(child);
    }
  }

  for (final folder in ['apps', 'packages', 'modules', 'examples']) {
    checkMembership(Directory('${root.path}/$folder'));
  }
  final byName = {for (final member in members) member.name: member};
  bool impureDependency(
    String name, [
    Set<String>? visited,
    bool allowFlutter = false,
  ]) {
    if (_isImpurePackage(name) && !(allowFlutter && name == 'flutter')) {
      return true;
    }
    final seen = visited ?? <String>{};
    if (!seen.add(name)) return false;
    return byName[name]?.dependencies.any(
          (dependency) => impureDependency(dependency, seen, allowFlutter),
        ) ??
        false;
  }

  for (final member in members.where((member) => member.path != '.')) {
    final manifestPath = '${member.path}/pubspec.yaml';
    for (final dependency in member.dependencies) {
      final target = byName[dependency];
      if (target != null && _badDirection(member, target)) {
        issues.add(
          ArchitectureIssue(
            'ARCH001',
            manifestPath,
            1,
            dependency,
            'Runtime dependency crosses the shared package / app / module boundary',
          ),
        );
      }
      if ((member.isPure || member.isUi) &&
          impureDependency(dependency, null, member.isUi)) {
        issues.add(
          ArchitectureIssue(
            'ARCH003',
            manifestPath,
            1,
            dependency,
            'Foundational/domain or pure UI package has a forbidden runtime dependency',
          ),
        );
      }
    }
    final lib = Directory('${root.path}/${member.path}/lib');
    if (!lib.existsSync()) continue;
    for (final file
        in lib
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      if (!file.path.endsWith('.dart') || _isGenerated(file.path)) continue;
      final path = relativeTo(root, file.path);
      final source = file.readAsStringSync();
      final parsed = parseString(
        content: source,
        path: file.path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        for (final error in parsed.errors) {
          issues.add(
            ArchitectureIssue(
              'ARCH000',
              path,
              parsed.lineInfo.getLocation(error.offset).lineNumber,
              'syntax',
              error.message,
            ),
          );
        }
        continue;
      }
      void report(String rule, AstNode node, String target, String message) {
        issues.add(
          ArchitectureIssue(
            rule,
            path,
            parsed.lineInfo.getLocation(node.offset).lineNumber,
            target,
            message,
          ),
        );
      }

      final memberSource = path.substring('${member.path}/lib/'.length);
      final isDomain =
          memberSource.split('/').contains('domain') || member.isPure;
      final presentation = memberSource.contains('presentation/');
      final isPage =
          presentation && !memberSource.contains('presentation/providers/');
      final layer = _featureLayer(memberSource);
      for (final directive
          in parsed.unit.directives.whereType<NamespaceDirective>()) {
        final uris = [
          directive.uri,
          ...directive.configurations.map((c) => c.uri),
        ];
        for (final literal in uris) {
          final uri = literal.stringValue;
          if (uri == null) continue;
          final package = packageName(uri);
          final destination = _resolveImport(root, file, member, byName, uri);
          final targetMember = destination?.$1;
          final targetSource = destination?.$2;
          if (targetMember != null && _badDirection(member, targetMember)) {
            report(
              'ARCH001',
              literal,
              uri,
              'Import/export crosses package direction',
            );
          }
          if (destination != null) {
            final targetModule = _moduleIdentity(targetMember!, targetSource!);
            final sourceModule = _moduleIdentity(member, memberSource);
            if (targetModule != null &&
                targetModule != sourceModule &&
                !_isModuleEntrypoint(targetMember, targetSource)) {
              report(
                'ARCH002',
                literal,
                uri,
                'Consume the module public entrypoint, not its implementation',
              );
            }
          }
          if (isDomain &&
              (uri == 'dart:ui' ||
                  _platformLibraries.contains(uri) ||
                  package != null &&
                      package != member.name &&
                      impureDependency(package) ||
                  !member.isPure &&
                      targetMember == member &&
                      targetSource != null &&
                      !targetSource.split('/').contains('domain') ||
                  targetSource != null &&
                      _isImplementationLayer(targetSource))) {
            report(
              'ARCH003',
              literal,
              uri,
              'Domain must not import UI, IO, network or implementation layers',
            );
          }
          if (member.isUi &&
              (_platformLibraries.contains(uri) ||
                  package != null &&
                      package != member.name &&
                      impureDependency(package, null, true) ||
                  targetSource != null &&
                      _isImplementationLayer(targetSource))) {
            report(
              'ARCH003',
              literal,
              uri,
              'Pure UI must not import platform IO, browser/media adapters, business state or implementation layers',
            );
          }
          if (isPage &&
              (uri == 'dart:io' ||
                  uri == 'dart:html' ||
                  package != null &&
                      (_networkPackages.contains(package) ||
                          package.endsWith('_api') ||
                          package.endsWith('_network') ||
                          package == 'koi_api_bootstrap') ||
                  targetSource != null &&
                      _featureLayer(targetSource) == 'data')) {
            report(
              'ARCH006',
              literal,
              uri,
              'Page/widget must consume providers instead of IO or data implementations',
            );
          }
          if ((layer == 'data' || layer == 'application') &&
              targetSource != null &&
              _featureLayer(targetSource) == 'presentation') {
            report(
              'ARCH008',
              literal,
              uri,
              'Data/application must not depend on presentation',
            );
          }
        }
      }
      parsed.unit.accept(_SourceVisitor(parsed.unit, memberSource, report));
    }
  }
  issues.sort(
    (a, b) => '${a.path}:${a.line}:${a.rule}'.compareTo(
      '${b.path}:${b.line}:${b.rule}',
    ),
  );
  return issues;
}

bool _isImplementationLayer(String source) =>
    {'data', 'application', 'presentation'}.contains(_featureLayer(source));

String? _featureLayer(String source) {
  final parts = source.split('/');
  final index = parts.indexOf('features');
  if (index >= 0 && parts.length > index + 2) return parts[index + 2];
  return null;
}

(WorkspaceMember, String)? _resolveImport(
  Directory root,
  File source,
  WorkspaceMember member,
  Map<String, WorkspaceMember> members,
  String uri,
) {
  if (uri.startsWith('dart:')) return null;
  final package = packageName(uri);
  if (package != null) {
    final target = members[package];
    if (target == null) return null;
    final slash = uri.indexOf('/');
    return slash < 0 ? null : (target, uri.substring(slash + 1));
  }
  final resolved = normalized(source.absolute.uri.resolve(uri).toFilePath());
  for (final candidate in members.values) {
    final prefix =
        '${normalized(Directory('${root.path}/${candidate.path}/lib').absolute.path)}/';
    if (resolved.startsWith(prefix)) {
      return (candidate, resolved.substring(prefix.length));
    }
  }
  return null;
}

String? _moduleIdentity(WorkspaceMember member, String source) {
  if (member.isModule) return member.name;
  final parts = source.split('/');
  final index = parts.indexOf('modules');
  if (index >= 0 && parts.length > index + 1) {
    return '${member.name}/${parts[index + 1]}';
  }
  return null;
}

bool _isModuleEntrypoint(WorkspaceMember member, String source) {
  if (member.isModule) return source == '${member.name}.dart';
  final parts = source.split('/');
  final index = parts.indexOf('modules');
  return index >= 0 &&
      parts.length == index + 3 &&
      parts.last == '${parts[index + 1]}.dart';
}

typedef _Report = void Function(
  String rule,
  AstNode node,
  String target,
  String message,
);

final class _SourceVisitor extends RecursiveAstVisitor<void> {
  _SourceVisitor(this.unit, this.path, this.report);
  final CompilationUnit unit;
  final String path;
  final _Report report;
  final List<Map<String, String?>> ioScopes = [{}];
  static const providerNames = {
    'Provider',
    'StateProvider',
    'StateNotifierProvider',
    'NotifierProvider',
    'AsyncNotifierProvider',
    'FutureProvider',
    'StreamProvider',
    'ChangeNotifierProvider',
    'StreamNotifierProvider',
  };
  static const ioTypes = {
    'File',
    'Directory',
    'FileSystemEntity',
    'Process',
    'RandomAccessFile',
  };

  bool imported(
    String symbol,
    String? prefix,
    bool Function(String uri) accepts,
  ) {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix ||
          !accepts(directive.uri.stringValue ?? '')) {
        continue;
      }
      if (directive.combinators.whereType<HideCombinator>().any(
        (c) => c.hiddenNames.any((n) => n.name == symbol),
      )) {
        continue;
      }
      final shows = directive.combinators.whereType<ShowCombinator>();
      if (shows.isNotEmpty &&
          !shows.every((c) => c.shownNames.any((n) => n.name == symbol))) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool isRiverpod(String symbol, String? prefix) => imported(
    symbol,
    prefix,
    (uri) => {
      'riverpod',
      'flutter_riverpod',
      'riverpod_annotation',
    }.contains(packageName(uri)),
  );
  bool isIo(String symbol, String? prefix) =>
      ioTypes.contains(symbol) &&
      imported(symbol, prefix, (uri) => uri == 'dart:io');
  bool annotated(NodeList<Annotation> metadata) => metadata.any((annotation) {
    final name = annotation.name.toSource().split('.');
    return {'riverpod', 'Riverpod'}.contains(name.last) &&
        isRiverpod(name.last, name.length == 2 ? name.first : null);
  });

  void checkProvider(AstNode node, String name) {
    if (_featureLayer(path) != null &&
        !path.contains('/presentation/providers/')) {
      report(
        'ARCH004',
        node,
        name,
        'Move the feature provider to presentation/providers',
      );
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (annotated(node.metadata)) checkProvider(node, node.name.lexeme);
    ioScopes.add({});
    try {
      super.visitFunctionDeclaration(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (annotated(node.metadata)) {
      checkProvider(node, node.namePart.typeName.lexeme);
    }
    ioScopes.add({});
    try {
      super.visitClassDeclaration(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    ioScopes.add({});
    try {
      super.visitMethodDeclaration(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    ioScopes.add({});
    try {
      super.visitFunctionExpression(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  @override
  void visitBlock(Block node) {
    ioScopes.add({});
    try {
      super.visitBlock(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  void handwritten(AstNode node, String symbol, String? prefix) {
    if (providerNames.contains(symbol) && isRiverpod(symbol, prefix)) {
      report(
        'ARCH005',
        node,
        symbol,
        'Declare providers with @riverpod/@Riverpod',
      );
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    handwritten(node, type.name.lexeme, type.importPrefix?.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    final type = node.type;
    for (final variable in node.variables) {
      final ioType =
          type is NamedType &&
              isIo(type.name.lexeme, type.importPrefix?.name.lexeme)
          ? type.name.lexeme
          : ioReceiver(variable.initializer);
      ioScopes.last[variable.name.lexeme] = ioType;
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    final type = node.type;
    if (type is NamedType &&
        isIo(type.name.lexeme, type.importPrefix?.name.lexeme)) {
      if (node.name != null) {
        ioScopes.last[node.name!.lexeme] = type.name.lexeme;
      }
    } else if (node.name != null) {
      ioScopes.last[node.name!.lexeme] = null;
    }
    super.visitRegularFormalParameter(node);
  }

  String? ioReceiver(Expression? expression) {
    if (expression is SimpleIdentifier) {
      if (isIo(expression.name, null)) return expression.name;
      for (final scope in ioScopes.reversed) {
        if (scope.containsKey(expression.name)) return scope[expression.name];
      }
      return null;
    }
    if (expression is PrefixedIdentifier &&
        isIo(expression.identifier.name, expression.prefix.name)) {
      return expression.identifier.name;
    }
    if (expression is InstanceCreationExpression) {
      final type = expression.constructorName.type;
      return isIo(type.name.lexeme, type.importPrefix?.name.lexeme)
          ? type.name.lexeme
          : null;
    }
    if (expression is MethodInvocation) {
      final prefix = expression.target is SimpleIdentifier
          ? (expression.target! as SimpleIdentifier).name
          : null;
      if (isIo(expression.methodName.name, prefix)) {
        return expression.methodName.name;
      }
    }
    if (expression is PropertyAccess) return ioReceiver(expression.target);
    return null;
  }

  bool restrictedSyncBody(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionExpression &&
          current.parent is! FunctionDeclaration) {
        return false;
      }
      if (current is FunctionDeclaration) {
        return annotated(current.metadata);
      }
      if (current is MethodDeclaration) {
        if (current.name.lexeme != 'build') return false;
        AstNode? owner = current.parent;
        while (owner != null && owner is! ClassDeclaration) {
          owner = owner.parent;
        }
        if (owner is! ClassDeclaration) return false;
        if (annotated(owner.metadata)) return true;
        final superclass = owner.extendsClause?.superclass.name.lexeme;
        return {
          'StatelessWidget',
          'State',
          'ConsumerWidget',
          'ConsumerState',
          'HookWidget',
          'HookConsumerWidget',
        }.contains(superclass);
      }
      current = current.parent;
    }
    return false;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final receiver = node.realTarget;
    if (providerNames.contains(name)) {
      handwritten(
        node,
        name,
        receiver is SimpleIdentifier ? receiver.name : null,
      );
    } else if (receiver != null) {
      // Provider.autoDispose / Provider.family are factory invocations in an
      // unresolved AST. Only match a provider imported from Riverpod.
      final root = receiver.toSource().split('.');
      if (root.length <= 3 && providerNames.contains(root.first)) {
        handwritten(node, root.first, null);
      }
      if (root.length >= 2 &&
          root.length <= 4 &&
          providerNames.contains(root[1])) {
        handwritten(node, root[1], root.first);
      }
    }
    if (name.endsWith('Sync') &&
        ioReceiver(receiver) != null &&
        restrictedSyncBody(node)) {
      report(
        'ARCH007',
        node,
        '${ioReceiver(receiver)}.$name',
        'Move synchronous IO out of widget/provider build',
      );
    }
    super.visitMethodInvocation(node);
  }
}

/// Exceptions are exact, justified, and fail when they no longer match. This
/// makes them reviewable debt rather than a permanent directory-wide bypass.
List<ArchitectureIssue> applyExceptions(
  List<ArchitectureIssue> issues,
  File file,
) {
  if (!file.existsSync()) return issues;
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (data['version'] != 1 || data['exceptions'] is! List) {
    throw const FormatException('Invalid architecture exception schema');
  }
  final remaining = [...issues];
  final seen = <String>{};
  for (final entry in data['exceptions'] as List<dynamic>) {
    if (entry is! Map<String, dynamic> ||
        entry.keys.toSet().difference({
          'rule',
          'path',
          'line',
          'target',
          'reason',
        }).isNotEmpty ||
        entry['rule'] is! String ||
        !architectureRules.containsKey(entry['rule']) ||
        entry['path'] is! String ||
        entry['line'] is! int ||
        (entry['line'] as int) < 1 ||
        entry['target'] is! String ||
        entry['reason'] is! String ||
        (entry['reason'] as String).trim().length < 12) {
      throw const FormatException(
        'Exception requires exact rule/path/line/target and a meaningful reason',
      );
    }
    final path = entry['path'] as String;
    if (path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        path.contains('\\') ||
        path.split('/').contains('..') ||
        path.contains('*')) {
      throw const FormatException(
        'Exception path must be exact and workspace-relative',
      );
    }
    final key = '${entry['rule']}:$path:${entry['line']}:${entry['target']}';
    if (!seen.add(key)) throw FormatException('Duplicate exception: $key');
    final matching = remaining
        .where(
          (issue) =>
              issue.rule == entry['rule'] &&
              issue.path == path &&
              issue.line == entry['line'] &&
              issue.target == entry['target'],
        )
        .toList();
    if (matching.length != 1) {
      remaining.add(
        ArchitectureIssue(
          'ARCH_EXCEPTION',
          path,
          entry['line'] as int,
          entry['target'] as String,
          'Stale or ambiguous exception: $key',
        ),
      );
    } else {
      remaining.remove(matching.single);
    }
  }
  return remaining;
}
