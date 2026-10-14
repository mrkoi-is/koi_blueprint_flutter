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
  'ARCH010': 'Review State responsibilities and lifecycle when instance fields exceed eight.',
  'ARCH011':
      'Review widget responsibilities and API when callbacks exceed four.',
  'ARCH012': 'Retired: media parsing belongs to product behavior tests.',
  'ARCH013': 'Shell coordinators must not import presentation.',
  'ARCH014': 'Async notifier methods assigning state after await must check ref.mounted.',
};

String normalized(String path) => path.replaceAll(r'\', '/');

/// 未解析语法树看不到 typedef 的底层函数类型，所以按名字认命令回调。
bool _isCommandCallback(
  TypeAnnotation? type, {
  Set<String> aliases = const {},
}) {
  if (type is GenericFunctionType) return true;
  if (type is! NamedType) return false;
  final name = type.name.lexeme;
  return name == 'Function' ||
      aliases.contains(name) ||
      name.endsWith('Callback') ||
      name == 'ValueChanged' ||
      name == 'ValueSetter' ||
      name == 'AsyncValueSetter' ||
      name == 'ValueGetter';
}

String relativeTo(Directory root, String path) {
  final relative = relativePathWithin(
    root.absolute.path,
    File(path).absolute.path,
  );
  if (relative == null) {
    throw FormatException('Path is outside workspace: $path');
  }
  return relative;
}

/// Lexical containment using the host's path semantics; no filesystem access.
/// Windows comparisons ignore case, while the returned relative spelling does not.
String? relativePathWithin(String root, String path, {bool? windows}) {
  final isWindows = windows ?? Platform.isWindows;
  String canonical(String value) => normalized(
    Uri.file(
      value,
      windows: isWindows,
    ).normalizePath().toFilePath(windows: isWindows),
  ).replaceFirst(RegExp(r'/+$'), '');
  final base = canonical(root);
  final absolute = canonical(path);
  final comparisonBase = isWindows ? base.toLowerCase() : base;
  final comparisonPath = isWindows ? absolute.toLowerCase() : absolute;
  if (comparisonPath == comparisonBase) return '.';
  if (!comparisonPath.startsWith('$comparisonBase/')) return null;
  return absolute.substring(base.length + 1);
}

enum ArchitectureSeverity { error, warning }

final class ArchitectureIssue {
  const ArchitectureIssue(
    this.rule,
    this.path,
    this.line,
    this.target,
    this.message, {
    this.measure,
    this.severity = ArchitectureSeverity.error,
  });
  final ArchitectureSeverity severity;
  final String rule;
  final String path;
  final int line;
  final String target;
  final String message;

  /// Field or callback count for ARCH010 and ARCH011. Exceptions budget against it.
  final int? measure;
  Map<String, Object> toJson() => {
    'severity': severity.name,
    'rule': rule,
    'path': path,
    'line': line,
    'target': target,
    'message': message,
    'measure': ?measure,
  };
  @override
  String toString() =>
      '$path:$line [${severity.name} $rule] $message ($target)';
}

Map<String, Object> architectureReport(List<ArchitectureIssue> issues) {
  final errors = issues
      .where((issue) => issue.severity == ArchitectureSeverity.error)
      .length;
  return {
    'ok': errors == 0,
    'issues': [for (final issue in issues) issue.toJson()],
    'summary': {'errors': errors, 'warnings': issues.length - errors},
  };
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
    String name, {
    Set<String>? visited,
    bool allowFlutter = false,
  }) {
    if (_isImpurePackage(name) && !(allowFlutter && name == 'flutter')) {
      return true;
    }
    final seen = visited ?? <String>{};
    if (!seen.add(name)) return false;
    return byName[name]?.dependencies.any(
          (dependency) => impureDependency(
            dependency,
            visited: seen,
            allowFlutter: allowFlutter,
          ),
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
          impureDependency(dependency, allowFlutter: member.isUi)) {
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
      void report(
        String rule,
        AstNode node,
        String target,
        String message, {
        int? measure,
      }) {
        issues.add(
          ArchitectureIssue(
            rule,
            path,
            parsed.lineInfo.getLocation(node.offset).lineNumber,
            target,
            message,
            measure: measure,
            severity: {'ARCH010', 'ARCH011'}.contains(rule)
                ? ArchitectureSeverity.warning
                : ArchitectureSeverity.error,
          ),
        );
      }

      final memberSource = path.substring('${member.path}/lib/'.length);
      final isDomain =
          memberSource.split('/').contains('domain') || member.isPure;
      final presentation = memberSource.contains('presentation/');
      final isPage =
          (presentation ||
              (_isFeatureUiPath(memberSource) &&
                  _containsWidgetOrState(parsed.unit))) &&
          !memberSource.contains('presentation/providers/');
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
                      impureDependency(package, allowFlutter: true) ||
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
          if (_isShellCoordinator(memberSource) &&
              (_importsPresentation(uri, targetSource) ||
                  _exportsPresentation(root, file, member, byName, uri, {}))) {
            report(
              'ARCH013',
              literal,
              uri,
              'Shell coordinators must not import presentation',
            );
          }
        }
      }
      parsed.unit.accept(
        _SourceVisitor(parsed.unit, memberSource, path, report),
      );
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

bool _isFeatureUiPath(String source) {
  final value = normalized(source);
  final parts = value.split('/');
  final index = parts.indexOf('features');
  if (index < 0 || value.endsWith('_capability.dart')) return false;
  final layer = _featureLayer(value);
  return !{'data', 'application', 'domain'}.contains(layer) &&
      !value.contains('presentation/providers/');
}

const _widgetOrStateSuperclasses = <String>{
  'StatelessWidget',
  'StatefulWidget',
  'ConsumerWidget',
  'ConsumerStatefulWidget',
  'HookWidget',
  'HookConsumerWidget',
  'State',
  'ConsumerState',
};

bool _containsWidgetOrState(CompilationUnit unit) =>
    unit.declarations.whereType<ClassDeclaration>().any(
      (decl) => _widgetOrStateSuperclasses.contains(
        decl.extendsClause?.superclass.name.lexeme,
      ),
    );

bool _isShellCoordinator(String memberSource) {
  final value = normalized(memberSource);
  return value.startsWith('shell/coordinators/') ||
      value.contains('/shell/coordinators/');
}

bool _importsPresentation(String uri, String? targetSource) {
  if (normalized(uri).contains('/presentation/')) return true;
  return targetSource != null &&
      normalized(targetSource).contains('/presentation/');
}

/// 跟随 workspace 内的重导出，防止 shared barrel 隐藏展示依赖。
bool _exportsPresentation(
  Directory root,
  File source,
  WorkspaceMember member,
  Map<String, WorkspaceMember> members,
  String uri,
  Set<String> visited,
) {
  final target = _resolveImport(root, source, member, members, uri);
  if (target == null) return false;
  if (_importsPresentation(uri, target.$2)) return true;
  final file = File('${root.path}/${target.$1.path}/lib/${target.$2}');
  if (!visited.add(normalized(file.absolute.path)) || !file.existsSync()) {
    return false;
  }
  final unit = parseString(
    content: file.readAsStringSync(),
    throwIfDiagnostics: false,
  ).unit;
  for (final directive in unit.directives.whereType<ExportDirective>()) {
    for (final literal in [
      directive.uri,
      ...directive.configurations.map((c) => c.uri),
    ]) {
      final next = literal.stringValue;
      if (next != null &&
          _exportsPresentation(root, file, target.$1, members, next, visited)) {
        return true;
      }
    }
  }
  return false;
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
    final relative = relativePathWithin(
      Directory('${root.path}/${candidate.path}/lib').absolute.path,
      resolved,
    );
    if (relative != null && relative != '.') {
      return (candidate, relative);
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
  String message, {
  int? measure,
});

final class _SourceVisitor extends RecursiveAstVisitor<void> {
  _SourceVisitor(this.unit, this.path, this.filePath, this.report);
  final CompilationUnit unit;
  final String path;
  final String filePath;
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
    final isAnnotatedNotifier = annotated(node.metadata);
    if (isAnnotatedNotifier) {
      checkProvider(node, node.namePart.typeName.lexeme);
    }
    final superclass = node.extendsClause?.superclass.name.lexeme;
    if (isAnnotatedNotifier || (superclass?.startsWith(r'_$') ?? false)) {
      checkAsyncNotifierMounted(node);
    }
    checkPresentationMass(node);
    ioScopes.add({});
    try {
      super.visitClassDeclaration(node);
    } finally {
      ioScopes.removeLast();
    }
  }

  void checkAsyncNotifierMounted(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    for (final method in node.body.members.whereType<MethodDeclaration>()) {
      if (method.name.lexeme == 'build' || !method.body.isAsynchronous) {
        continue;
      }
      final inspector = _AsyncStateAssignmentVisitor();
      method.body.accept(inspector);
      if (inspector.unsafeAssignments.isNotEmpty) {
        report(
          'ARCH014',
          inspector.unsafeAssignments.first,
          '$className.${method.name.lexeme}',
          'Check ref.mounted after await before assigning notifier state',
        );
      }
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
    var current = node.parent;
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
        var owner = current.parent;
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

  void checkPresentationMass(ClassDeclaration node) {
    final normalizedPath = normalized(path);
    if ((!normalizedPath.contains('/presentation/') &&
            !_isFeatureUiPath(normalizedPath)) ||
        normalizedPath.contains('/presentation/providers/')) {
      return;
    }
    final superclass = node.extendsClause?.superclass.name.lexeme;
    final name = node.namePart.typeName.lexeme;
    if ({'State', 'ConsumerState'}.contains(superclass)) {
      final fields = node.body.members
          .whereType<FieldDeclaration>()
          .where((field) => !field.isStatic)
          .fold<int>(
            0,
            (count, field) => count + field.fields.variables.length,
          );
      if (fields > 8) {
        report(
          'ARCH010',
          node,
          name,
          'Review responsibilities, state ownership and lifecycle; field count alone does not require a provider',
          measure: fields,
        );
      }
    }
    if ({
      'StatelessWidget',
      'StatefulWidget',
      'ConsumerWidget',
      'ConsumerStatefulWidget',
    }.contains(superclass)) {
      final unit = node.thisOrAncestorOfType<CompilationUnit>()!;
      final aliases = {
        for (final alias in unit.declarations.whereType<GenericTypeAlias>())
          if (alias.type is GenericFunctionType) alias.name.lexeme,
        for (final alias in unit.declarations.whereType<FunctionTypeAlias>())
          alias.name.lexeme,
      };
      final fieldNames = {
        for (final field in node.body.members.whereType<FieldDeclaration>())
          if (!field.isStatic &&
              _isCommandCallback(field.fields.type, aliases: aliases))
            for (final variable in field.fields.variables) variable.name.lexeme,
      };
      var callbacks = fieldNames.length;
      for (final constructor
          in node.body.members.whereType<ConstructorDeclaration>()) {
        final names = {...fieldNames};
        for (final parameter in constructor.parameters.parameters) {
          if (parameter.functionTypedSuffix != null ||
              _isCommandCallback(parameter.type, aliases: aliases)) {
            final name = parameter.name?.lexeme;
            if (name != null) names.add(name);
          }
        }
        if (names.length > callbacks) callbacks = names.length;
      }
      if (callbacks > 4) {
        report(
          'ARCH011',
          node,
          name,
          'Review responsibilities and callback API; callback count alone does not require provider injection',
          measure: callbacks,
        );
      }
    }
  }
}

final class _AsyncStateAssignmentVisitor extends RecursiveAstVisitor<void> {
  _AsyncStateAssignmentVisitor({
    this.pending = false,
    Set<AssignmentExpression>? unsafeAssignments,
  }) : unsafeAssignments = unsafeAssignments ?? {};

  // null = unreachable; true = a reachable path has suspended without a guard.
  // Normal, return and exception paths stay separate until a finally block.
  bool? pending;
  bool? returned;
  bool? thrown;
  final Set<AssignmentExpression> unsafeAssignments;

  static bool? _join(bool? first, bool? second) => first == null
      ? second
      : second == null
      ? first
      : first || second;

  _AsyncStateAssignmentVisitor _run(AstNode? node, bool? entry) {
    final branch = _AsyncStateAssignmentVisitor(
      pending: entry,
      unsafeAssignments: unsafeAssignments,
    );
    if (entry != null) node?.accept(branch);
    return branch;
  }

  void _mergeExits(_AsyncStateAssignmentVisitor branch) {
    returned = _join(returned, branch.returned);
    thrown = _join(thrown, branch.thrown);
  }

  bool _isRef(Expression expression) =>
      expression is SimpleIdentifier && expression.name == 'ref' ||
      expression is PropertyAccess &&
          expression.target is ThisExpression &&
          expression.propertyName.name == 'ref';

  bool _isMounted(Expression expression) =>
      expression is PrefixedIdentifier &&
          expression.prefix.name == 'ref' &&
          expression.identifier.name == 'mounted' ||
      expression is PropertyAccess &&
          expression.target != null &&
          _isRef(expression.target!) &&
          expression.propertyName.name == 'mounted';

  // Facts belong to the evaluated branch, never to a mere read of ref.mounted.
  (bool?, bool?) _condition(Expression condition, bool? entry) {
    if (entry == null) return (null, null);
    if (condition is ParenthesizedExpression) {
      return _condition(condition.expression, entry);
    }
    if (_isMounted(condition)) return (false, entry);
    if (condition is BooleanLiteral) {
      return condition.value ? (entry, null) : (null, entry);
    }
    if (condition is PrefixExpression && condition.operator.lexeme == '!') {
      final (yes, no) = _condition(condition.operand, entry);
      return (no, yes);
    }
    if (condition is BinaryExpression) {
      final operator = condition.operator.lexeme;
      if (operator == '&&' || operator == '||') {
        final (leftYes, leftNo) = _condition(condition.leftOperand, entry);
        final (rightYes, rightNo) = _condition(
          condition.rightOperand,
          operator == '&&' ? leftYes : leftNo,
        );
        return operator == '&&'
            ? (rightYes, _join(leftNo, rightNo))
            : (_join(leftYes, rightYes), rightNo);
      }
    }
    final evaluated = _run(condition, entry);
    _mergeExits(evaluated);
    return (evaluated.pending, evaluated.pending);
  }

  @override
  void visitBlock(Block node) {
    for (final statement in node.statements) {
      if (pending == null) break;
      statement.accept(this);
    }
  }

  void _mayThrow() => thrown = _join(thrown, pending);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    _mayThrow();
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    super.visitFunctionExpressionInvocation(node);
    _mayThrow();
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);
    _mayThrow();
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (_isMounted(node)) return;
    super.visitPropertyAccess(node);
    _mayThrow();
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_isMounted(node)) return;
    super.visitPrefixedIdentifier(node);
    _mayThrow();
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    super.visitIndexExpression(node);
    _mayThrow();
  }

  @override
  void visitAsExpression(AsExpression node) {
    super.visitAsExpression(node);
    _mayThrow();
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    super.visitPostfixExpression(node);
    // Both a failed null assertion and an overloaded update can throw.
    _mayThrow();
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    super.visitPrefixExpression(node);
    // Boolean negation itself is not an overloaded operation. Its operand's
    // effects are visited, while _condition preserves mounted guard facts.
    if (node.operator.lexeme != '!') _mayThrow();
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitIfStatement(IfStatement node) {
    final bool? yes;
    final bool? no;
    if (node.caseClause == null) {
      (yes, no) = _condition(node.expression, pending);
    } else {
      // Matching a boolean against a pattern is not a truthiness test.
      final evaluated = _run(node.expression, pending);
      node.caseClause!.accept(evaluated);
      _mergeExits(evaluated);
      yes = no = evaluated.pending;
    }
    final thenBranch = _run(node.thenStatement, yes);
    final elseBranch = _run(node.elseStatement, no);
    _mergeExits(thenBranch);
    _mergeExits(elseBranch);
    pending = _join(thenBranch.pending, elseBranch.pending);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final (yes, no) = _condition(node.condition, pending);
    final thenBranch = _run(node.thenExpression, yes);
    final elseBranch = _run(node.elseExpression, no);
    _mergeExits(thenBranch);
    _mergeExits(elseBranch);
    pending = _join(thenBranch.pending, elseBranch.pending);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    node.expression.accept(this);
    final entry = pending;
    // Keep the unmatched path conservatively, including pattern switches.
    var normal = entry;
    for (final member in node.members) {
      final branch = _run(member, entry);
      _mergeExits(branch);
      normal = _join(normal, branch.pending);
    }
    pending = normal;
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    node.expression.accept(this);
    final entry = pending;
    var normal = entry;
    for (final arm in node.cases) {
      final branch = _run(arm, entry);
      _mergeExits(branch);
      normal = _join(normal, branch.pending);
    }
    pending = normal;
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if ({'&&', '||'}.contains(node.operator.lexeme)) {
      final (yes, no) = _condition(node, pending);
      pending = _join(yes, no);
    } else {
      super.visitBinaryExpression(node);
      // Arithmetic, comparison and equality can throw or call user operators.
      // Null coalescing only contributes the effects of its operands.
      if (node.operator.lexeme != '??') _mayThrow();
    }
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    node.expression?.accept(this);
    returned = _join(returned, pending);
    pending = null;
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    node.expression.accept(this);
    thrown = _join(thrown, pending);
    pending = null;
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    thrown = _join(thrown, pending);
    pending = null;
  }

  @override
  void visitTryStatement(TryStatement node) {
    final body = _run(node.body, pending);
    var normal = body.pending;
    var returns = body.returned;
    var errors = node.catchClauses.any((clause) => clause.exceptionType == null)
        ? null
        : body.thrown;
    for (final clause in node.catchClauses) {
      final handler = _run(clause.body, body.thrown);
      normal = _join(normal, handler.pending);
      returns = _join(returns, handler.returned);
      errors = _join(errors, handler.thrown);
    }
    final finallyBlock = node.finallyBlock;
    if (finallyBlock != null) {
      final afterNormal = _run(finallyBlock, normal);
      final afterReturn = _run(finallyBlock, returns);
      final afterError = _run(finallyBlock, errors);
      normal = afterNormal.pending;
      returns = _join(afterReturn.pending, afterNormal.returned);
      errors = _join(afterError.pending, afterNormal.thrown);
      returns = _join(
        returns,
        _join(afterReturn.returned, afterError.returned),
      );
      errors = _join(errors, _join(afterReturn.thrown, afterError.thrown));
    }
    pending = normal;
    returned = _join(returned, returns);
    thrown = _join(thrown, errors);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    node.expression.accept(this);
    if (pending != null) {
      pending = true;
      thrown = true;
    }
  }

  // Loops are conservative: a suspension in any iteration invalidates facts
  // at the next iteration and after the loop. Guards inside the body still work.
  void _loop(AstNode node, void Function() visitChildren) {
    final awaits = _AwaitFinder();
    node.accept(awaits);
    final entry = pending;
    if (entry != null && awaits.found) pending = true;
    visitChildren();
    pending = awaits.found && entry != null ? true : _join(entry, pending);
  }

  @override
  void visitForStatement(ForStatement node) {
    _loop(node, () => super.visitForStatement(node));
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _loop(node, () => super.visitWhileStatement(node));
  }

  @override
  void visitDoStatement(DoStatement node) {
    _loop(node, () => super.visitDoStatement(node));
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
    final lhs = node.leftHandSide;
    final writesState =
        lhs is SimpleIdentifier && lhs.name == 'state' ||
        lhs is PropertyAccess &&
            lhs.target is ThisExpression &&
            lhs.propertyName.name == 'state';
    if (writesState && pending == true) {
      unsafeAssignments.add(node);
    }
    _mayThrow();
  }
}

final class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitAwaitExpression(AwaitExpression node) => found = true;

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForStatement(node);
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
          'budget',
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
    final retired = entry['rule'] == 'ARCH012';
    final counted = entry['rule'] == 'ARCH010' || entry['rule'] == 'ARCH011';
    final budget = entry['budget'];
    if (counted) {
      if (budget is! int || budget < 0) {
        throw const FormatException(
          'ARCH010 and ARCH011 exceptions require a non-negative integer budget',
        );
      }
    } else if (entry.containsKey('budget')) {
      throw const FormatException(
        'Only ARCH010 and ARCH011 exceptions accept a budget',
      );
    }
    final path = entry['path'] as String;
    if (path.startsWith('/') ||
        RegExp('^[A-Za-z]:').hasMatch(path) ||
        path.contains(r'\') ||
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
    if (retired || matching.length != 1) {
      remaining.add(
        ArchitectureIssue(
          'ARCH_EXCEPTION',
          path,
          entry['line'] as int,
          entry['target'] as String,
          retired
              ? 'Retired ARCH012 exception; remove it: $key'
              : 'Stale or ambiguous exception: $key',
          severity: counted || retired
              ? ArchitectureSeverity.warning
              : ArchitectureSeverity.error,
        ),
      );
    } else if (counted &&
        (matching.single.measure == null ||
            matching.single.measure! > (budget as int))) {
      remaining.add(
        ArchitectureIssue(
          'ARCH_EXCEPTION',
          path,
          entry['line'] as int,
          entry['target'] as String,
          'Exception budget exceeded: $key measure ${matching.single.measure} > budget $budget',
          severity: ArchitectureSeverity.warning,
        ),
      );
    } else {
      remaining.remove(matching.single);
    }
  }
  return remaining;
}
