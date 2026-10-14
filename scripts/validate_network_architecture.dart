import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:koi_swagger_parser/koi_swagger_parser.dart';
import 'package:yaml/yaml.dart';

/// Best-effort static lint for the repository's network architecture.
///
/// Passing this script proves only that the checked declarations and source
/// patterns are internally consistent. It does not prove runtime egress
/// completeness, backend reachability, release safety, or migration acceptance.
const _gateScope = 'basic_lint';

// Examples and optional business modules obey the same boundary/TLS rules.
const _scanRoots = ['apps', 'packages', 'modules', 'examples'];

const _allowedCategories = <String>{
  'business_api',
  'ai_stream',
  'transfer',
  'remote_asset',
  'media',
  'webview',
  'platform_sdk',
  'device_link',
};

const _allowedDataClassifications = <String>{
  'public',
  'internal',
  'personal',
  'sensitive',
  'template',
};

const _allowedContracts = <String>{
  'openapi',
  'compatibility',
  'manual',
  'external',
  'plugin',
  'platform',
};

const _allowedAuthentication = <String>{
  'none',
  'project_adapter',
  'signed',
  'external_credential',
  'platform_sdk',
};

const _allowedAuthFailurePolicies = <String>{
  'global_session',
  'per_backend',
  'business_error',
  'none',
  'plugin_managed',
};

const _allowedRetryPolicies = <String>{
  'never',
  'endpoint_semantics',
  'idempotency_key',
  'plugin_managed',
};

const _allowedDynamicUrlPolicies = <String>{
  'fixed_origin',
  'allowlist',
  'runtime_validated',
  'platform_managed',
  'runtime_supplied',
};

const _allowedHostPolicies = <String>{
  'declared',
  'provider_managed',
  'runtime_supplied',
};

const _allowedSecurityPolicies = <String>{
  'strict_tls',
  'runtime_validated',
  'provider_managed',
  'development_only',
};

const _allowedNativeSecurityExceptionKinds = <String>{
  'android_domain_cleartext',
};

const _allowedNonProductionEnvironments = <String>{'development', 'testing'};

const _allowedNonProductionSourceSets = <String>{
  'debug',
  'dev',
  'development',
  'test',
  'testing',
  'local',
};

const _allowedAuthorities = <String>{
  'server',
  'compatibility',
  'template_example',
};

const _allowedMigrationStacks = <String>{
  'legacy',
  'koi_generated',
  'external_gateway',
  'retired',
};

const _allowedMigrationStatuses = <String>{
  'pending',
  'migrating',
  'migrated',
  'quarantined',
  'exception',
  'retired',
};

const _allowedHttpMethods = <String>{
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
};

const _defaultPresentationForbidden = <String, String>{
  'package:dio/dio.dart': 'Presentation 不能导入 Dio',
  'package:http/http.dart': 'Presentation 不能导入 package:http',
  'package:koi_network/': 'Presentation 不能导入 koi_network',
  'package:koi_api_bootstrap/': 'Presentation 不能导入 Koi Runtime',
  'package:retrofit/': 'Presentation 不能导入 Retrofit',
  'KoiNetworkServiceManager': 'Presentation 不能取得 Koi 全局 ServiceManager',
  'KoiDioFactory': 'Presentation 不能取得 Koi DioFactory',
  'KoiApiRuntime': 'Presentation 不能取得 KoiApiRuntime',
  'OpenAIClient(': 'Presentation 不能直接创建外部 AI Client',
};

Future<void> main() async {
  final errors = <String>[];
  final manifest = _validateEgressManifest(errors);

  _validateDartBoundaries(errors, manifest);
  _validateGeneratedApiPackageBoundaries(errors);
  _validateNativeAndTlsSecurity(errors, manifest);
  await _validateOpenApiProvenance(errors, template: manifest.template);
  _validateMigrationManifest(errors, manifest);

  if (errors.isNotEmpty) {
    stderr.writeln('网络架构基础 lint 失败：');
    for (final error in errors) {
      stderr.writeln('- $error');
    }
    stderr.writeln('提示：本门禁是静态基础 lint，不替代运行时出口审计和迁移验收。');
    exitCode = 1;
    return;
  }

  stdout.writeln('网络架构基础 lint 通过');
  stdout.writeln('范围：静态声明与已知源码模式；不等于运行时出口完整或迁移验收完成。');
}

_EgressManifest _validateEgressManifest(List<String> errors) {
  final file = File('tool/network/egress_manifest.json');
  final decoded = _readJsonObject(file, errors, 'egress manifest');
  if (decoded == null) return _EgressManifest.fallback();
  _validateKnownFields(
    decoded,
    const {
      r'$schema',
      'schemaVersion',
      'gateScope',
      'template',
      'project',
      'boundaries',
      'migration',
      'nativeSecurityExceptions',
      'entries',
    },
    errors,
    'egress manifest',
  );

  if (decoded['schemaVersion'] != 1) {
    errors.add('egress manifest schemaVersion 必须为 1');
  }
  if (decoded['gateScope'] != _gateScope) {
    errors.add('egress manifest gateScope 必须明确为 $_gateScope');
  }
  final project = _requiredString(
    decoded,
    'project',
    errors,
    'egress manifest',
  );
  final template = decoded['template'];
  if (template is! bool) {
    errors.add('egress manifest template 必须是布尔值');
  }

  final schemaPath = decoded[r'$schema'];
  if (schemaPath is String && schemaPath.trim().isNotEmpty) {
    final resolved = _resolveRelativeTo(file, schemaPath);
    if (!resolved.existsSync()) {
      errors.add('egress manifest 引用的 schema 不存在：${resolved.path}');
    }
  }

  final presentationSegments = <String>{};
  final forbiddenSymbols = <String>{};
  final transportConstructionPaths = <String>{};
  final boundaries = decoded['boundaries'];
  if (boundaries is! Map<String, dynamic>) {
    errors.add('egress manifest 缺少 boundaries 对象');
  } else {
    _validateKnownFields(
      boundaries,
      const {
        'presentationPathSegments',
        'forbiddenSymbols',
        'transportConstructionPaths',
      },
      errors,
      'egress boundaries',
    );
    presentationSegments.addAll(
      _requiredStringList(
        boundaries,
        'presentationPathSegments',
        errors,
        'egress boundaries',
      ).map(_normalizePathSegment),
    );
    if (boundaries.containsKey('transportConstructionPaths')) {
      for (final rawPath in _requiredStringList(
        boundaries,
        'transportConstructionPaths',
        errors,
        'egress boundaries',
        allowEmpty: true,
      )) {
        final path = _normalizeRepoPath(rawPath);
        if (!_isSafeRepoRelativePath(rawPath) ||
            !_scanRoots.any((root) => path.startsWith('$root/')) ||
            !_isRuntimeDartPath(path) ||
            !path.endsWith('.dart') ||
            !File(path).existsSync()) {
          errors.add(
            'transportConstructionPaths 必须是扫描范围内存在的 Dart 源文件：$rawPath',
          );
        } else if (!transportConstructionPaths.add(path)) {
          errors.add('transportConstructionPaths 不能重复：$path');
        }
      }
    }
    forbiddenSymbols.addAll(
      _requiredStringList(
        boundaries,
        'forbiddenSymbols',
        errors,
        'egress boundaries',
        allowEmpty: true,
      ),
    );
  }
  presentationSegments.removeWhere((value) => value.isEmpty);
  if (presentationSegments.isEmpty) {
    errors.add('egress boundaries.presentationPathSegments 不能为空');
    presentationSegments.addAll(const {'presentation', 'page', 'pages'});
  }

  final migration = _parseMigrationConfig(decoded['migration'], errors);
  final nativeSecurityExceptions = _parseNativeSecurityExceptions(
    decoded['nativeSecurityExceptions'],
    template == true,
    errors,
  );
  final declaredOrigins = <String>{};
  final entries = decoded['entries'];
  if (entries is! List) {
    errors.add('egress manifest entries 必须是数组（离线项目可以为空）');
  } else {
    final ids = <String>{};
    for (var index = 0; index < entries.length; index++) {
      final rawEntry = entries[index];
      if (rawEntry is! Map<String, dynamic>) {
        errors.add('egress entries[$index] 必须是对象');
        continue;
      }
      _validateEgressEntry(
        rawEntry,
        index,
        ids,
        declaredOrigins,
        template == true,
        errors,
      );
    }
  }

  return _EgressManifest(
    template: template == true,
    project: project ?? '',
    declaredOrigins: declaredOrigins,
    presentationPathSegments: presentationSegments,
    forbiddenSymbols: forbiddenSymbols,
    transportConstructionPaths: transportConstructionPaths,
    migration: migration,
    nativeSecurityExceptions: nativeSecurityExceptions,
  );
}

Map<String, _NativeSecurityException> _parseNativeSecurityExceptions(
  Object? raw,
  bool template,
  List<String> errors,
) {
  if (raw is! List) {
    errors.add('egress manifest nativeSecurityExceptions 必须是数组');
    return const {};
  }

  final result = <String, _NativeSecurityException>{};
  final ids = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final item = raw[index];
    if (item is! Map<String, dynamic>) {
      errors.add('nativeSecurityExceptions[$index] 必须是对象');
      continue;
    }
    final context = 'nativeSecurityExceptions[$index]';
    _validateKnownFields(
      item,
      const {
        'id',
        'kind',
        'path',
        'sourceSet',
        'reason',
        'owner',
        'approvedBy',
        'environments',
        'expiresAt',
        'evidence',
        'configSha256',
      },
      errors,
      context,
    );
    final id = _requiredString(item, 'id', errors, context);
    if (id != null && !ids.add(id)) {
      errors.add('native security exception id 重复：$id');
    }
    final kind = _validateEnumField(
      item,
      'kind',
      _allowedNativeSecurityExceptionKinds,
      errors,
      context,
    );
    final path = _requiredString(item, 'path', errors, context);
    final sourceSet = _requiredString(item, 'sourceSet', errors, context);
    if (path != null) {
      _validateExistingRepoPath(path, errors, '$context path');
    }
    if (sourceSet != null) {
      final normalizedSourceSet = sourceSet.toLowerCase();
      if (!_allowedNonProductionSourceSets.contains(normalizedSourceSet)) {
        errors.add(
          '$context 的 sourceSet `$sourceSet` 不在已知非生产 allowlist：'
          '${_allowedNonProductionSourceSets.join(', ')}',
        );
      }
      if (path != null &&
          !_pathBelongsToAndroidSourceSet(path, normalizedSourceSet)) {
        errors.add('$context path 必须位于 Android src/$sourceSet/ source set 内');
      }
    }
    final reason = _requiredString(item, 'reason', errors, context);
    final owner = _requiredString(item, 'owner', errors, context);
    final approvedBy = _requiredString(item, 'approvedBy', errors, context);

    final environments = _requiredStringList(
      item,
      'environments',
      errors,
      context,
    );
    if (environments.toSet().length != environments.length) {
      errors.add('$context 的 environments 不能包含重复值');
    }
    for (final environment in environments) {
      if (!_allowedNonProductionEnvironments.contains(environment)) {
        errors.add('$context 只能批准 development/testing，不能包含 $environment');
      }
    }
    _validateExpiry(item['expiresAt'], true, errors, context);
    final evidence = _requiredStringList(item, 'evidence', errors, context);
    for (final value in evidence) {
      _validateEvidence(value, errors, context);
    }
    final configSha256 = _requiredString(item, 'configSha256', errors, context);
    if (path != null && configSha256 != null) {
      _validateFileHash(path, configSha256, errors, '$context config');
    }
    if (!template) {
      for (final value in [reason, owner, approvedBy, ...evidence]) {
        if (value != null) {
          _rejectPlaceholder(value, errors, context);
        }
      }
    }

    if (kind != null && path != null && configSha256 != null) {
      final normalizedPath = _normalizePath(path);
      final key = '$kind|$normalizedPath';
      if (result.containsKey(key)) {
        errors.add('native security exception 重复覆盖：$kind $normalizedPath');
      } else {
        result[key] = _NativeSecurityException(
          kind: kind,
          path: normalizedPath,
          configSha256: configSha256.toLowerCase(),
        );
      }
    }
  }
  return result;
}

bool _pathBelongsToAndroidSourceSet(String path, String sourceSet) => RegExp(
  '/android/(?:app/)?src/${RegExp.escape(sourceSet)}/',
  caseSensitive: false,
).hasMatch(_normalizePath(path));

void _validateEgressEntry(
  Map<String, dynamic> entry,
  int index,
  Set<String> ids,
  Set<String> declaredOrigins,
  bool template,
  List<String> errors,
) {
  final context = 'egress entries[$index]';
  _validateKnownFields(
    entry,
    const {
      'id',
      'category',
      'purpose',
      'owner',
      'dataClassification',
      'transport',
      'contract',
      'authentication',
      'authFailurePolicy',
      'retryPolicy',
      'dynamicUrlPolicy',
      'hostPolicy',
      'securityPolicy',
      'securityPolicyDetails',
      'provider',
      'hosts',
      'tls',
      'testEvidence',
      'developmentOnly',
    },
    errors,
    context,
  );
  final id = _requiredString(entry, 'id', errors, context);
  if (id != null && !ids.add(id)) {
    errors.add('egress id 重复：$id');
  }
  final label = id ?? 'entries[$index]';

  _requiredString(entry, 'purpose', errors, 'egress $label');
  final owner = _requiredString(entry, 'owner', errors, 'egress $label');
  _requiredString(entry, 'transport', errors, 'egress $label');
  final category = _validateEnumField(
    entry,
    'category',
    _allowedCategories,
    errors,
    'egress $label',
  );
  final dataClassification = _validateEnumField(
    entry,
    'dataClassification',
    _allowedDataClassifications,
    errors,
    'egress $label',
  );
  _validateEnumField(
    entry,
    'contract',
    _allowedContracts,
    errors,
    'egress $label',
  );
  final authentication = _validateEnumField(
    entry,
    'authentication',
    _allowedAuthentication,
    errors,
    'egress $label',
  );
  final authFailurePolicy = _validateEnumField(
    entry,
    'authFailurePolicy',
    _allowedAuthFailurePolicies,
    errors,
    'egress $label',
  );
  _validateEnumField(
    entry,
    'retryPolicy',
    _allowedRetryPolicies,
    errors,
    'egress $label',
  );
  final dynamicUrlPolicy = _validateEnumField(
    entry,
    'dynamicUrlPolicy',
    _allowedDynamicUrlPolicies,
    errors,
    'egress $label',
  );
  final hostPolicy = _validateEnumField(
    entry,
    'hostPolicy',
    _allowedHostPolicies,
    errors,
    'egress $label',
  );
  final securityPolicy = _validateEnumField(
    entry,
    'securityPolicy',
    _allowedSecurityPolicies,
    errors,
    'egress $label',
  );
  final securityPolicyDetails = _requiredString(
    entry,
    'securityPolicyDetails',
    errors,
    'egress $label',
  );

  if (authentication == 'none' &&
      authFailurePolicy != null &&
      authFailurePolicy != 'none' &&
      authFailurePolicy != 'business_error') {
    errors.add('egress $label 无认证出口不能使用 $authFailurePolicy 认证失败策略');
  }

  final developmentOnly = entry['developmentOnly'] == true;
  if (entry.containsKey('developmentOnly') &&
      entry['developmentOnly'] is! bool) {
    errors.add('egress $label developmentOnly 必须是布尔值');
  }
  if (developmentOnly && (!template || securityPolicy != 'development_only')) {
    errors.add(
      'egress $label developmentOnly 仅可用于 template=true 的 development_only 样例',
    );
  }
  if (!developmentOnly && securityPolicy == 'development_only') {
    errors.add('egress $label development_only 必须显式声明 developmentOnly=true');
  }
  if (!developmentOnly && dynamicUrlPolicy == 'runtime_supplied') {
    errors.add(
      'egress $label runtime_supplied URL 必须显式声明 developmentOnly=true',
    );
  }
  final runtimeSupplied = hostPolicy == 'runtime_supplied';
  if (runtimeSupplied) {
    if (!developmentOnly || dynamicUrlPolicy != 'runtime_supplied') {
      errors.add('egress $label runtime_supplied 仅用于显式开发样例，不代表已验证的动态 URL 策略');
    }
    if (!entry.containsKey('hosts') ||
        !entry.containsKey('tls') ||
        entry['hosts'] != null ||
        entry['tls'] != null) {
      errors.add('egress $label runtime_supplied 应将 hosts/tls 设为 null');
    }
  }

  final providerManaged = hostPolicy == 'provider_managed';
  if (providerManaged) {
    if (category != 'platform_sdk' || dynamicUrlPolicy != 'platform_managed') {
      errors.add(
        'egress $label 只有 platform_sdk + platform_managed '
        '可以使用 provider_managed Host',
      );
    }
    if (securityPolicy != 'provider_managed') {
      errors.add(
        'egress $label 的 provider_managed Host 必须使用 '
        'provider_managed 安全策略',
      );
    }
    final provider = _requiredString(
      entry,
      'provider',
      errors,
      'egress $label',
    );
    if (!template && provider != null) {
      _rejectPlaceholder(provider, errors, 'egress $label provider');
    }
    if (!entry.containsKey('hosts') ||
        !entry.containsKey('tls') ||
        entry['hosts'] != null ||
        entry['tls'] != null) {
      errors.add('egress $label 的 provider_managed Host 应将 hosts/tls 设为 null');
    }
  } else if (!runtimeSupplied) {
    final hosts = entry['hosts'];
    if (hosts is! Map<String, dynamic>) {
      errors.add('egress $label 的 declared Host 必须提供 hosts 对象');
    } else {
      _validateKnownFields(
        hosts,
        developmentOnly
            ? const {'development'}
            : const {'development', 'staging', 'production'},
        errors,
        'egress $label hosts',
      );
      for (final environment
          in developmentOnly
              ? const ['development']
              : const ['development', 'staging', 'production']) {
        final rawHost = hosts[environment];
        if (rawHost is! String || rawHost.trim().isEmpty) {
          errors.add('egress $label 缺少非空 $environment Host');
          continue;
        }
        final uri = Uri.tryParse(rawHost);
        if (uri == null ||
            !uri.isAbsolute ||
            uri.host.isEmpty ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          errors.add('egress $label 的 $environment Host 必须是绝对 HTTP(S) URL');
          continue;
        }
        if (uri.userInfo.isNotEmpty) {
          errors.add('egress $label 的 $environment Host 不能包含用户名或密码');
        }
        if (uri.hasQuery || uri.hasFragment) {
          errors.add('egress $label 的 $environment Host 不能包含 query 或 fragment');
        }
        if (!template && _isReservedTemplateHost(uri.host)) {
          errors.add(
            'egress $label 的 $environment Host 在 template=false 时不能使用'
            '示例保留域名：${uri.host}',
          );
        }
        if (environment != 'development' && uri.scheme != 'https') {
          errors.add('egress $label 的 $environment Host 必须使用 HTTPS');
        }
        declaredOrigins.add(uri.origin);
      }
    }

    final tls = entry['tls'];
    if (tls is! Map<String, dynamic>) {
      errors.add('egress $label 的 declared Host 必须提供 tls 对象');
    } else {
      _validateKnownFields(
        tls,
        developmentOnly ? const {} : const {'staging', 'production'},
        errors,
        'egress $label tls',
      );
      for (final environment
          in developmentOnly
              ? const <String>[]
              : const ['staging', 'production']) {
        if (tls[environment] != 'strict') {
          errors.add('egress $label 的 $environment TLS 必须为 strict');
        }
      }
    }
  }

  final testEvidence = _requiredStringList(
    entry,
    'testEvidence',
    errors,
    'egress $label',
  );
  for (final evidence in testEvidence) {
    _validateEvidence(evidence, errors, 'egress $label');
  }
  if (!template) {
    if (dataClassification == 'template') {
      errors.add('egress $label 在 template=false 时不能使用 template 数据分类');
    }
    if (owner != null) {
      _rejectPlaceholder(owner, errors, 'egress $label owner');
    }
    if (securityPolicyDetails != null) {
      _rejectPlaceholder(
        securityPolicyDetails,
        errors,
        'egress $label securityPolicyDetails',
      );
    }
    for (final evidence in testEvidence) {
      _rejectPlaceholder(evidence, errors, 'egress $label testEvidence');
    }
  }
}

_MigrationConfig _parseMigrationConfig(Object? raw, List<String> errors) {
  if (raw is! Map<String, dynamic>) {
    errors.add('egress manifest 缺少 migration 对象');
    return _MigrationConfig.disabled();
  }
  _validateKnownFields(
    raw,
    const {'enabled', 'manifest', 'requireZeroLegacy', 'defaultStack'},
    errors,
    'egress migration',
  );
  final enabled = raw['enabled'];
  final requireZeroLegacy = raw['requireZeroLegacy'];
  if (enabled is! bool) {
    errors.add('egress migration.enabled 必须是布尔值');
  }
  if (requireZeroLegacy is! bool) {
    errors.add('egress migration.requireZeroLegacy 必须是布尔值');
  }
  final manifestPath = _requiredString(
    raw,
    'manifest',
    errors,
    'egress migration',
  );
  final defaultStack = _validateEnumField(
    raw,
    'defaultStack',
    const {'legacy', 'koi_generated'},
    errors,
    'egress migration',
  );
  if (manifestPath != null && !_isSafeRepoRelativePath(manifestPath)) {
    errors.add('egress migration.manifest 必须是仓库内相对路径：$manifestPath');
  }
  return _MigrationConfig(
    enabled: enabled == true,
    manifestPath: manifestPath ?? 'tool/network/migration_manifest.json',
    requireZeroLegacy: requireZeroLegacy == true,
    defaultStack: defaultStack ?? 'legacy',
  );
}

void _validateDartBoundaries(List<String> errors, _EgressManifest manifest) {
  final forbidden = <String, String>{..._defaultPresentationForbidden};
  for (final symbol in manifest.forbiddenSymbols) {
    forbidden.putIfAbsent(symbol, () => 'Presentation 命中项目禁止符号 `$symbol`');
  }

  for (final file in _sourceFiles(_scanRoots, {'.dart'})) {
    final path = _normalizePath(file.path);
    final source = _readSource(file, errors);
    if (source == null) continue;

    final pathSegments = path.split('/').map(_normalizePathSegment).toSet();
    final presentation = pathSegments.any(
      manifest.presentationPathSegments.contains,
    );
    if (presentation) {
      for (final pattern in forbidden.entries) {
        if (source.contains(pattern.key)) {
          errors.add('${pattern.value}：$path');
        }
      }
      if (RegExp(r'''package:[a-z0-9_]+_api/''').hasMatch(source)) {
        errors.add('Presentation 不能直接导入生成 API 包：$path');
      }
    }

    final compositionRoot =
        path.endsWith('/bootstrap.dart') ||
        path.contains('/core/network/') ||
        manifest.transportConstructionPaths.contains(path);
    if (_isRuntimeDartPath(path) &&
        !compositionRoot &&
        RegExp(r'''\bDio\s*\(''').hasMatch(source)) {
      errors.add(
        'Dio 只能在 Composition Root/core/network 或登记的 transport 文件创建：$path',
      );
    }

    if (_isRuntimeDartPath(path)) {
      for (final match in RegExp(
        r'''https?://[^\s'"<>]+''',
        caseSensitive: false,
      ).allMatches(source)) {
        final rawUrl = match.group(0);
        final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
        if (uri != null &&
            uri.host.isNotEmpty &&
            !manifest.declaredOrigins.contains(uri.origin)) {
          errors.add('代码中的网络 origin 未登记到 egress manifest：${uri.origin}（$path）');
        }
      }
    }
  }
}

void _validateGeneratedApiPackageBoundaries(List<String> errors) {
  final appPackageNames = <String>{};
  final apps = Directory('apps');
  if (apps.existsSync()) {
    for (final entity in apps.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _readPubspecPackageName(
        File('${entity.path}/pubspec.yaml'),
        errors,
      );
      if (name != null) appPackageNames.add(name);
    }
  }

  final packages = Directory('packages');
  if (!packages.existsSync()) return;
  for (final entity in packages.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final packagePath = _normalizeRepoPath(entity.path);
    if (!packagePath.split('/').last.endsWith('_api')) continue;
    final pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      errors.add('生成 API 包缺少 pubspec.yaml：$packagePath');
      continue;
    }
    final decoded = _readYamlMap(pubspec, errors, '$packagePath pubspec');
    if (decoded != null) {
      for (final sectionName in const [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides',
      ]) {
        final section = decoded[sectionName];
        if (section is! Map) continue;
        for (final dependency in section.keys.map((key) => key.toString())) {
          if (_isForbiddenGeneratedApiDependency(dependency, appPackageNames)) {
            errors.add(
              '纯生成 API 包 $packagePath 不能依赖 $dependency '
              '($sectionName)',
            );
          }
        }
      }
    }

    final lib = Directory('${entity.path}/lib');
    if (!lib.existsSync()) continue;
    for (final source
        in lib
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      if (!source.path.endsWith('.dart')) continue;
      final contents = _readSource(source, errors);
      if (contents == null) continue;
      final directives = RegExp(
        r'''^\s*(?:import|export)\s+['"]package:([^/'"]+)/''',
        multiLine: true,
      ).allMatches(contents);
      for (final directive in directives) {
        final dependency = directive.group(1)!;
        if (_isForbiddenGeneratedApiDependency(dependency, appPackageNames)) {
          errors.add(
            '纯生成 API 包源码不能导入或重导出 $dependency：'
            '${_normalizeRepoPath(source.path)}',
          );
        }
      }
    }
  }
}

bool _isForbiddenGeneratedApiDependency(
  String dependency,
  Set<String> appPackageNames,
) =>
    dependency == 'koi_network' ||
    dependency == 'koi_api_bootstrap' ||
    dependency.endsWith('_network') ||
    appPackageNames.contains(dependency);

String? _readPubspecPackageName(File file, List<String> errors) {
  if (!file.existsSync()) return null;
  final decoded = _readYamlMap(file, errors, _normalizeRepoPath(file.path));
  final name = decoded?['name'];
  return name is String && name.trim().isNotEmpty ? name : null;
}

YamlMap? _readYamlMap(File file, List<String> errors, String context) {
  try {
    final decoded = loadYaml(file.readAsStringSync());
    if (decoded is! YamlMap) {
      errors.add('$context 必须是 YAML 对象');
      return null;
    }
    return decoded;
  } on FileSystemException catch (error) {
    errors.add('$context 无法读取：${error.message}');
  } on YamlException catch (error) {
    errors.add('$context 不是合法 YAML：$error');
  }
  return null;
}

void _validateNativeAndTlsSecurity(
  List<String> errors,
  _EgressManifest manifest,
) {
  final extensions = <String>{
    '.dart',
    '.xml',
    '.plist',
    '.java',
    '.kt',
    '.kts',
    '.swift',
    '.m',
    '.mm',
  };
  for (final file in _sourceFiles(_scanRoots, extensions)) {
    final path = _normalizePath(file.path);
    final lowerPath = path.toLowerCase();
    final isDartRuntime = lowerPath.endsWith('.dart') && path.contains('/lib/');
    final isNativeSource =
        path.contains('/android/') ||
        path.contains('/ios/') ||
        path.contains('/macos/');
    if (!isDartRuntime && !isNativeSource) continue;

    final source = _readSource(file, errors);
    if (source == null) continue;

    if (RegExp(
      r'''android:usesCleartextTraffic\s*=\s*["']true["']''',
      caseSensitive: false,
    ).hasMatch(source)) {
      errors.add('Android 禁止全局 usesCleartextTraffic=true：$path');
    }
    if (RegExp(
      r'''<base-config\b[^>]*cleartextTrafficPermitted\s*=\s*["']true["']''',
      caseSensitive: false,
    ).hasMatch(source)) {
      errors.add('Android 禁止 base-config 全局允许明文流量：$path');
    }
    if (RegExp(
      r'''<domain-config\b[^>]*cleartextTrafficPermitted\s*=\s*["']true["']''',
      caseSensitive: false,
    ).hasMatch(source)) {
      final clearlyNonProduction = _isClearlyNonProductionAndroidSource(path);
      final exception =
          manifest.nativeSecurityExceptions['android_domain_cleartext|$path'];
      if (!clearlyNonProduction) {
        errors.add('Android domain-config 明文流量只能位于已知非生产 source set：$path');
      } else if (exception == null) {
        errors.add(
          'Android domain-config 明文流量必须登记带期限、证据和配置 SHA-256 '
          '的批准例外：$path',
        );
      }
    }
    if (_plistBooleanEnabled(source, 'NSAllowsArbitraryLoads') ||
        _plistBooleanEnabled(source, 'NSAllowsArbitraryLoadsInWebContent') ||
        _plistBooleanEnabled(source, 'NSAllowsArbitraryLoadsForMedia') ||
        _plistBooleanEnabled(source, 'NSExceptionAllowsInsecureHTTPLoads')) {
      errors.add('Apple 平台禁止 ATS 全局或例外允许不安全 HTTP：$path');
    }

    if (RegExp(
      r'''validateCertificate\s*:\s*false''',
      caseSensitive: false,
    ).hasMatch(source)) {
      errors.add('禁止关闭网络证书校验 validateCertificate=false：$path');
    }
    if (_containsAlwaysTrueBadCertificateCallback(source)) {
      errors.add('禁止 badCertificateCallback 无条件接受证书：$path');
    }
    if (_containsUnconditionalServerTrustProceed(source)) {
      errors.add('WebView 禁止无条件接受无效服务器证书：$path');
    }
    if (_containsUnconditionalNativeSslProceed(source)) {
      errors.add('原生 WebView 禁止在 SSL 错误回调中调用 proceed()：$path');
    }
    if (_containsAlwaysTrueHostnameVerifier(source)) {
      errors.add('禁止 HostnameVerifier 无条件返回 true：$path');
    }
  }
}

bool _isClearlyNonProductionAndroidSource(String path) {
  final match = RegExp(
    r'''/android/(?:app/)?src/([^/]+)/''',
    caseSensitive: false,
  ).firstMatch(_normalizePath(path));
  final sourceSet = match?.group(1)?.toLowerCase();
  return sourceSet != null &&
      _allowedNonProductionSourceSets.contains(sourceSet);
}

Future<void> _validateOpenApiProvenance(
  List<String> errors, {
  required bool template,
}) async {
  final generatedApiPackages = <String>{};
  final packages = Directory('packages');
  if (packages.existsSync()) {
    for (final entity in packages.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final path = _normalizePath(entity.path)
          .replaceFirst(RegExp(r'''/$'''), '');
      final name = path.split('/').last;
      if (name.endsWith('_api')) generatedApiPackages.add(path);
    }
  }

  final activeConfigs = _listActiveSwaggerParserConfigs();
  final file = File('tool/openapi/PROVENANCE.json');
  if (!file.existsSync()) {
    if (generatedApiPackages.isNotEmpty) {
      errors.add(
        '检测到生成 API 包 ${generatedApiPackages.join(', ')}，但缺少 '
        'tool/openapi/PROVENANCE.json',
      );
    }
    for (final config in activeConfigs) {
      errors.add(
        '活动 parser 配置未被 OpenAPI provenance 覆盖：'
        '${_normalizeRepoPath(config.path)}',
      );
    }
    return;
  }

  final decoded = _readJsonObject(file, errors, 'OpenAPI provenance');
  if (decoded == null) return;
  _validateKnownFields(
    decoded,
    const {'schemaVersion', 'contracts'},
    errors,
    'OpenAPI provenance',
  );
  if (decoded['schemaVersion'] != 1) {
    errors.add('OpenAPI provenance schemaVersion 必须为 1');
  }
  final contracts = decoded['contracts'];
  if (contracts is! List || contracts.isEmpty) {
    errors.add('OpenAPI provenance contracts 必须是非空数组');
    return;
  }

  final ids = <String>{};
  final coveredOutputPackages = <String>{};
  final provenanceBindings = <_OpenApiProvenanceBinding>[];
  final lockedParserVersion = _readLockedPackageVersion(
    'koi_swagger_parser',
    errors,
  );
  for (var index = 0; index < contracts.length; index++) {
    final rawContract = contracts[index];
    if (rawContract is! Map<String, dynamic>) {
      errors.add('OpenAPI provenance contracts[$index] 必须是对象');
      continue;
    }
    _validateProvenanceContract(
      rawContract,
      index,
      ids,
      coveredOutputPackages,
      provenanceBindings,
      lockedParserVersion,
      template,
      errors,
    );
  }

  for (final package in generatedApiPackages.difference(
    coveredOutputPackages,
  )) {
    errors.add('生成 API 包未被 provenance 覆盖：$package');
  }

  await _validateActiveSwaggerParserConfigs(
    activeConfigs,
    provenanceBindings,
    errors,
  );
}

void _validateProvenanceContract(
  Map<String, dynamic> contract,
  int index,
  Set<String> ids,
  Set<String> coveredOutputPackages,
  List<_OpenApiProvenanceBinding> provenanceBindings,
  String? lockedKoiSwaggerParserVersion,
  bool template,
  List<String> errors,
) {
  final context = 'OpenAPI provenance contracts[$index]';
  _validateKnownFields(
    contract,
    const {
      'id',
      'authority',
      'sourceUrl',
      'fetchedAt',
      'sourceFile',
      'sourceSha256',
      'overlayFile',
      'overlaySha256',
      'overlayPurpose',
      'overlayOwner',
      'overlayRemovalCriteria',
      'compatibilityReason',
      'compatibilityOwner',
      'compatibilityRemoveWhen',
      'parser',
      'parserVersion',
      'configFile',
      'configSha256',
      'generationCommand',
      'outputPackage',
    },
    errors,
    context,
  );
  final id = _requiredString(contract, 'id', errors, context);
  if (id != null && !ids.add(id)) {
    errors.add('OpenAPI provenance contract id 重复：$id');
  }
  final label = id ?? 'contracts[$index]';
  final authority = _validateEnumField(
    contract,
    'authority',
    _allowedAuthorities,
    errors,
    'OpenAPI contract $label',
  );
  if (!template && authority == 'template_example') {
    errors.add(
      'OpenAPI contract $label 在 template=false 时不能使用 template_example authority',
    );
  }

  final sourceUrl = contract['sourceUrl'];
  if (sourceUrl != null) {
    final valid =
        sourceUrl is String &&
        (authority == 'template_example'
            ? _isAbsoluteSourceUri(sourceUrl)
            : _isAbsoluteHttpUrl(sourceUrl));
    if (!valid) {
      errors.add(
        'OpenAPI contract $label 的 sourceUrl 必须是合法绝对来源 URI；'
        'server/compatibility 仅允许 HTTP(S)',
      );
    }
    if (sourceUrl is String && _hasUriUserInfo(sourceUrl)) {
      errors.add('OpenAPI contract $label 的 sourceUrl 不能包含用户名或密码');
    }
    if (sourceUrl is String && _hasUriQueryOrFragment(sourceUrl)) {
      errors.add('OpenAPI contract $label 的 sourceUrl 不能包含 query 或 fragment');
    }
    if (!template && sourceUrl is String) {
      final uri = Uri.tryParse(sourceUrl);
      if (uri != null && _isReservedTemplateHost(uri.host)) {
        errors.add(
          'OpenAPI contract $label 在 template=false 时不能使用示例保留域名：'
          '${uri.host}',
        );
      }
    }
  } else if (authority == 'server' || authority == 'template_example') {
    errors.add('OpenAPI contract $label 的 $authority authority 必须提供 sourceUrl');
  }

  final fetchedAt = _requiredString(
    contract,
    'fetchedAt',
    errors,
    'OpenAPI contract $label',
  );
  if (fetchedAt != null &&
      (!fetchedAt.contains('T') || DateTime.tryParse(fetchedAt) == null)) {
    errors.add('OpenAPI contract $label 的 fetchedAt 必须是 ISO-8601 日期时间');
  }

  final sourceFile = _requiredString(
    contract,
    'sourceFile',
    errors,
    'OpenAPI contract $label',
  );
  final sourceSha = _requiredString(
    contract,
    'sourceSha256',
    errors,
    'OpenAPI contract $label',
  );
  if (sourceFile != null && sourceSha != null) {
    _validateFileHash(
      sourceFile,
      sourceSha,
      errors,
      'OpenAPI contract $label source',
    );
    if (sourceFile.toLowerCase().endsWith('.json')) {
      _validateOpenApiJson(
        File(sourceFile),
        errors,
        'OpenAPI contract $label source',
      );
    }
  }

  final overlayFile = contract['overlayFile'];
  final overlaySha = contract['overlaySha256'];
  if (overlayFile == null) {
    if (overlaySha != null) {
      errors.add(
        'OpenAPI contract $label 没有 overlayFile 时 overlaySha256 必须为 null',
      );
    }
  } else if (overlayFile is! String || overlayFile.trim().isEmpty) {
    errors.add('OpenAPI contract $label 的 overlayFile 必须是非空路径或 null');
  } else {
    if (overlaySha is! String || overlaySha.trim().isEmpty) {
      errors.add('OpenAPI contract $label 提供 overlayFile 时必须提供 overlaySha256');
    } else {
      _validateFileHash(
        overlayFile,
        overlaySha,
        errors,
        'OpenAPI contract $label overlay',
      );
    }
    for (final field in const [
      'overlayPurpose',
      'overlayOwner',
      'overlayRemovalCriteria',
    ]) {
      final value = _requiredString(
        contract,
        field,
        errors,
        'OpenAPI contract $label',
      );
      if (value != null) {
        _rejectPlaceholder(value, errors, 'OpenAPI contract $label $field');
      }
    }
  }

  if (authority == 'compatibility') {
    for (final field in const [
      'compatibilityReason',
      'compatibilityOwner',
      'compatibilityRemoveWhen',
    ]) {
      final value = _requiredString(
        contract,
        field,
        errors,
        'OpenAPI contract $label',
      );
      if (value != null) {
        _rejectPlaceholder(value, errors, 'OpenAPI contract $label $field');
      }
    }
  }

  final parser = _requiredString(
    contract,
    'parser',
    errors,
    'OpenAPI contract $label',
  );
  if (parser != null) {
    _rejectPlaceholder(parser, errors, 'OpenAPI contract $label parser');
  }
  final parserVersion = _requiredString(
    contract,
    'parserVersion',
    errors,
    'OpenAPI contract $label',
  );
  if (parserVersion != null && _looksLikePlaceholder(parserVersion)) {
    errors.add('OpenAPI contract $label 的 parserVersion 不能是占位值');
  }
  if (parser == 'koi_swagger_parser' &&
      parserVersion != null &&
      lockedKoiSwaggerParserVersion != null &&
      parserVersion != lockedKoiSwaggerParserVersion) {
    errors.add(
      'OpenAPI contract $label 的 parserVersion 与 pubspec.lock 不一致：'
      '声明 $parserVersion，锁定 $lockedKoiSwaggerParserVersion',
    );
  }

  final configFile = _requiredString(
    contract,
    'configFile',
    errors,
    'OpenAPI contract $label',
  );
  if (configFile != null) {
    _validateExistingRepoPath(
      configFile,
      errors,
      'OpenAPI contract $label configFile',
    );
    final configSha = _requiredString(
      contract,
      'configSha256',
      errors,
      'OpenAPI contract $label',
    );
    if (configSha != null) {
      _validateFileHash(
        configFile,
        configSha,
        errors,
        'OpenAPI contract $label config',
      );
    }
  }
  final generationCommand = _requiredString(
    contract,
    'generationCommand',
    errors,
    'OpenAPI contract $label',
  );
  if (generationCommand != null) {
    _rejectPlaceholder(
      generationCommand,
      errors,
      'OpenAPI contract $label generationCommand',
    );
  }

  final outputPackage = _requiredString(
    contract,
    'outputPackage',
    errors,
    'OpenAPI contract $label',
  );
  if (outputPackage != null) {
    if (!_isSafeRepoRelativePath(outputPackage)) {
      errors.add('OpenAPI contract $label 的 outputPackage 必须是仓库内相对路径');
    } else {
      final normalized = _normalizePath(outputPackage)
          .replaceFirst(RegExp(r'''/$'''), '');
      if (!normalized.startsWith('packages/') ||
          !normalized.split('/').last.endsWith('_api')) {
        errors.add(
          'OpenAPI contract $label 的 outputPackage 必须指向 packages/*_api',
        );
      }
      if (!Directory(normalized).existsSync()) {
        errors.add('OpenAPI contract $label 的 outputPackage 不存在：$normalized');
      } else {
        coveredOutputPackages.add(normalized);
      }
    }
  }

  final effectiveInputFile = overlayFile is String ? overlayFile : sourceFile;
  if (parser == 'koi_swagger_parser' &&
      id != null &&
      sourceFile != null &&
      configFile != null &&
      outputPackage != null &&
      effectiveInputFile != null &&
      _isSafeRepoRelativePath(effectiveInputFile) &&
      _isSafeRepoRelativePath(configFile) &&
      _isSafeRepoRelativePath(outputPackage)) {
    provenanceBindings.add(
      _OpenApiProvenanceBinding(
        id: id,
        inputFile: _normalizeRepoPath(effectiveInputFile),
        configFile: _normalizeRepoPath(configFile),
        outputPackage: _normalizeRepoPath(outputPackage),
      ),
    );
  }
}

List<File> _listActiveSwaggerParserConfigs() {
  final directory = Directory('tool/koi_swagger_parser');
  if (!directory.existsSync()) return const [];
  final configs = directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) {
        final name = _normalizePath(file.path).split('/').last;
        final isYaml = name.endsWith('.yaml') || name.endsWith('.yml');
        final isExample =
            name.endsWith('.example.yaml') || name.endsWith('.example.yml');
        return isYaml && !isExample;
      })
      .toList();
  configs.sort((left, right) => left.path.compareTo(right.path));
  return configs;
}

String? _readLockedPackageVersion(String packageName, List<String> errors) {
  final lockFile = File('pubspec.lock');
  if (!lockFile.existsSync()) {
    errors.add('OpenAPI provenance 校验需要 pubspec.lock');
    return null;
  }
  try {
    final decoded = loadYaml(lockFile.readAsStringSync());
    final packages = decoded is Map ? decoded['packages'] : null;
    final package = packages is Map ? packages[packageName] : null;
    final version = package is Map ? package['version'] : null;
    if (version is! String || version.trim().isEmpty) {
      errors.add('pubspec.lock 未锁定 $packageName 版本');
      return null;
    }
    return version;
  } on FileSystemException catch (error) {
    errors.add('pubspec.lock 无法读取：${error.message}');
  } on YamlException catch (error) {
    errors.add('pubspec.lock 不是合法 YAML：$error');
  }
  return null;
}

Future<void> _validateActiveSwaggerParserConfigs(
  List<File> activeConfigs,
  List<_OpenApiProvenanceBinding> provenanceBindings,
  List<String> errors,
) async {
  final activeConfigPaths = activeConfigs
      .map((file) => _normalizeRepoPath(file.path))
      .toSet();
  for (final binding in provenanceBindings) {
    if (!activeConfigPaths.contains(binding.configFile)) {
      errors.add(
        'OpenAPI contract ${binding.id} 的 configFile 不是活动 parser 配置：'
        '${binding.configFile}',
      );
    }
  }

  final outputOwners = <String, String>{};
  for (final configFile in activeConfigs) {
    final configPath = _normalizeRepoPath(configFile.path);
    final bindings = provenanceBindings
        .where((binding) => binding.configFile == configPath)
        .toList();
    KoiSwaggerConfig config;
    try {
      config = await KoiSwaggerConfig.load(
        configPath: configFile.absolute.path,
        workingDirectory: Directory.current.absolute.path,
      );
    } on Object catch (error) {
      errors.add('活动 parser 配置无法加载 $configPath：$error');
      continue;
    }

    final sourceFiles = <String>{};
    for (var index = 0; index < config.input.swaggerUrls.length; index++) {
      final source = _canonicalRepoFile(
        config.input.swaggerUrls[index],
        errors,
        '活动 parser 配置 $configPath 的 enabled input[$index]',
      );
      if (source != null && !sourceFiles.add(source)) {
        errors.add('活动 parser 配置 $configPath 重复引用输入：$source');
      }
    }
    final outputPackage = _resolveGeneratedOutputPackage(
      config,
      configPath,
      errors,
    );
    if (outputPackage != null) {
      final previousOwner = outputOwners[outputPackage];
      if (previousOwner != null && previousOwner != configPath) {
        errors.add(
          '多个活动 parser 配置写入同一 output package：'
          '$previousOwner、$configPath -> $outputPackage',
        );
      } else {
        outputOwners[outputPackage] = configPath;
      }
    }

    if (bindings.isEmpty) {
      if (sourceFiles.isEmpty || outputPackage == null) {
        errors.add('活动 parser 配置未被 OpenAPI provenance 覆盖：$configPath');
      } else {
        for (final inputFile in sourceFiles) {
          errors.add(
            '活动 parser 配置未被 OpenAPI provenance 覆盖：$configPath；'
            'input=$inputFile；output=$outputPackage',
          );
        }
      }
      continue;
    }

    final seenSources = <String>{};
    for (final binding in bindings) {
      if (!seenSources.add(binding.inputFile)) {
        errors.add(
          'OpenAPI provenance 重复绑定同一活动输入：'
          '$configPath；input=${binding.inputFile}',
        );
      }
      if (!sourceFiles.contains(binding.inputFile)) {
        errors.add(
          'OpenAPI contract ${binding.id} 的生成输入不在配置 enabled inputs 中：'
          '声明 ${binding.inputFile}；实际 ${sourceFiles.join(', ')}',
        );
      }
      if (outputPackage != null && binding.outputPackage != outputPackage) {
        errors.add(
          'OpenAPI contract ${binding.id} 的 outputPackage 与活动配置不一致：'
          '声明 ${binding.outputPackage}，配置输出 $outputPackage',
        );
      }
    }

    for (final sourceFile in sourceFiles.difference(seenSources)) {
      errors.add(
        '活动 parser 配置未被 OpenAPI provenance 覆盖：$configPath；'
        'input=$sourceFile；output=${outputPackage ?? '<invalid>'}',
      );
    }
  }
}

String? _canonicalRepoFile(
  String rawPath,
  List<String> errors,
  String context,
) {
  final uri = Uri.tryParse(rawPath);
  if (uri == null || uri.isAbsolute && uri.scheme != 'file') {
    errors.add('$context 必须使用仓库内本地 OpenAPI：$rawPath');
    return null;
  }
  if (rawPath.startsWith('file://')) {
    errors.add('$context 必须使用仓库内相对路径，不能使用 file URI：$rawPath');
    return null;
  }
  final file = File(rawPath);
  if (!file.existsSync()) {
    errors.add('$context 文件不存在：$rawPath');
    return null;
  }
  try {
    return _canonicalRepoPath(file.resolveSymbolicLinksSync(), errors, context);
  } on FileSystemException catch (error) {
    errors.add('$context 无法解析真实路径：${error.message}');
    return null;
  }
}

String? _resolveGeneratedOutputPackage(
  KoiSwaggerConfig config,
  String configPath,
  List<String> errors,
) {
  final outputPaths = <String, String>{
    'base_dir': config.output.baseDir,
    'api_dir': config.output.apiDir,
    'models_dir': config.output.modelsDir,
  };
  String? package;
  for (final entry in outputPaths.entries) {
    final candidate = _findContainingApiPackage(
      entry.value,
      errors,
      '活动 parser 配置 $configPath 的 output.${entry.key}',
    );
    if (candidate == null) continue;
    if (package != null && package != candidate) {
      errors.add(
        '活动 parser 配置 $configPath 的 base/api/models 输出必须位于同一 API 包：'
        '$package、$candidate',
      );
    } else {
      package = candidate;
    }
  }
  return package;
}

String? _findContainingApiPackage(
  String rawPath,
  List<String> errors,
  String context,
) {
  final directory = Directory(rawPath);
  if (!directory.existsSync()) {
    errors.add('$context 目录不存在；请先完成生成：$rawPath');
    return null;
  }
  try {
    final root = Directory.current.resolveSymbolicLinksSync();
    var current = Directory(directory.resolveSymbolicLinksSync());
    final relativeOutput = _canonicalRepoPath(current.path, errors, context);
    if (relativeOutput == null) return null;
    while (true) {
      if (File('${current.path}/pubspec.yaml').existsSync()) {
        final packagePath = _canonicalRepoPath(current.path, errors, context);
        if (packagePath == null) return null;
        final segments = packagePath.split('/');
        if (segments.length != 2 ||
            segments.first != 'packages' ||
            !segments.last.endsWith('_api')) {
          errors.add('$context 必须位于 packages/*_api：$relativeOutput');
          return null;
        }
        return packagePath;
      }
      if (current.path == root) break;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    errors.add('$context 找不到所属 pubspec.yaml：$relativeOutput');
  } on FileSystemException catch (error) {
    errors.add('$context 无法解析真实路径：${error.message}');
  }
  return null;
}

String? _canonicalRepoPath(
  String canonicalPath,
  List<String> errors,
  String context,
) {
  try {
    final root = _normalizePath(Directory.current.resolveSymbolicLinksSync());
    final normalized = _normalizePath(canonicalPath);
    if (!normalized.startsWith('$root/')) {
      errors.add('$context 解析后必须位于仓库内：$canonicalPath');
      return null;
    }
    return normalized.substring(root.length + 1);
  } on FileSystemException catch (error) {
    errors.add('$context 无法解析仓库真实路径：${error.message}');
    return null;
  }
}

void _validateMigrationManifest(List<String> errors, _EgressManifest egress) {
  final config = egress.migration;
  if (!config.enabled) return;

  final file = File(config.manifestPath);
  final decoded = _readJsonObject(file, errors, 'network migration manifest');
  if (decoded == null) return;
  _validateKnownFields(
    decoded,
    const {r'$schema', 'schemaVersion', 'project', 'entries'},
    errors,
    'network migration manifest',
  );
  if (decoded['schemaVersion'] != 1) {
    errors.add('network migration manifest schemaVersion 必须为 1');
  }
  final project = _requiredString(
    decoded,
    'project',
    errors,
    'network migration manifest',
  );
  if (project != null &&
      egress.project.isNotEmpty &&
      project != egress.project) {
    errors.add('network migration manifest project 必须与 egress project 一致');
  }
  final entries = decoded['entries'];
  if (entries is! List || entries.isEmpty) {
    errors.add('启用迁移门禁时 migration manifest entries 必须是非空数组');
    return;
  }

  final operationKeys = <String>{};
  for (var index = 0; index < entries.length; index++) {
    final rawEntry = entries[index];
    if (rawEntry is! Map<String, dynamic>) {
      errors.add('migration entries[$index] 必须是对象');
      continue;
    }
    _validateMigrationEntry(rawEntry, index, config, operationKeys, errors);
  }
}

void _validateMigrationEntry(
  Map<String, dynamic> entry,
  int index,
  _MigrationConfig config,
  Set<String> operationKeys,
  List<String> errors,
) {
  final context = 'migration entries[$index]';
  _validateKnownFields(
    entry,
    const {
      'backend',
      'method',
      'path',
      'uiReachable',
      'consumer',
      'currentStack',
      'targetStack',
      'status',
      'owner',
      'reason',
      'expiresAt',
      'evidence',
    },
    errors,
    context,
  );
  final backend = _requiredString(entry, 'backend', errors, context);
  final rawMethod = _requiredString(entry, 'method', errors, context);
  final method = rawMethod?.toUpperCase();
  if (method != null && !_allowedHttpMethods.contains(method)) {
    errors.add('$context 使用未知 method：$rawMethod');
  }
  final path = _requiredString(entry, 'path', errors, context);
  if (path != null &&
      (!path.startsWith('/') || Uri.tryParse(path)?.hasScheme == true)) {
    errors.add('$context path 必须是以 / 开头的相对 API 路径');
  }
  if (backend != null && method != null && path != null) {
    final key = '$backend $method $path';
    if (!operationKeys.add(key)) {
      errors.add('migration manifest 接口重复：$key');
    }
  }

  final uiReachable = entry['uiReachable'];
  if (uiReachable is! bool) {
    errors.add('$context 的 uiReachable 必须是布尔值');
  }
  final consumer = _requiredString(entry, 'consumer', errors, context);
  final currentStack = _validateEnumField(
    entry,
    'currentStack',
    _allowedMigrationStacks,
    errors,
    context,
  );
  final targetStack = _validateEnumField(
    entry,
    'targetStack',
    _allowedMigrationStacks,
    errors,
    context,
  );
  final status = _validateEnumField(
    entry,
    'status',
    _allowedMigrationStatuses,
    errors,
    context,
  );
  final owner = _requiredString(entry, 'owner', errors, context);
  final reason = _requiredString(entry, 'reason', errors, context);
  if (owner != null) {
    _rejectPlaceholder(owner, errors, '$context owner');
  }
  if (reason != null) {
    _rejectPlaceholder(reason, errors, '$context reason');
  }
  final evidence = _requiredStringList(
    entry,
    'evidence',
    errors,
    context,
    allowEmpty: true,
  );

  if (uiReachable == true && status != 'retired' && consumer != null) {
    _validateExistingRepoPath(consumer, errors, '$context consumer');
  }
  final evidenceRequired =
      uiReachable == true ||
      currentStack == 'legacy' ||
      status == 'exception' ||
      status == 'quarantined';
  if (evidenceRequired && evidence.isEmpty) {
    errors.add('$context 的 UI 可达、Legacy 或例外接口必须提供 evidence');
  }
  for (final item in evidence) {
    _validateEvidence(item, errors, context);
  }

  if (status == 'migrated') {
    if (currentStack != targetStack) {
      errors.add('$context 标记 migrated 时 currentStack 必须等于 targetStack');
    }
    if (uiReachable == true && currentStack != config.defaultStack) {
      errors.add('$context 的 UI 可达已迁移接口必须使用默认栈 ${config.defaultStack}');
    }
  }
  if (uiReachable == true &&
      status != 'exception' &&
      status != 'quarantined' &&
      status != 'retired' &&
      targetStack != config.defaultStack) {
    errors.add('$context 的 UI 可达接口 targetStack 必须是 ${config.defaultStack}');
  }
  if (status == 'retired' && uiReachable == true) {
    errors.add('$context 标记 retired 时 uiReachable 必须为 false');
  }
  if (config.requireZeroLegacy &&
      uiReachable == true &&
      currentStack == 'legacy') {
    errors.add('$context 仍是 UI 可达 Legacy 接口，不满足 requireZeroLegacy');
  }

  final requiresExpiry =
      (uiReachable == true && currentStack == 'legacy') ||
      status == 'pending' ||
      status == 'migrating' ||
      status == 'quarantined' ||
      status == 'exception';
  _validateExpiry(entry['expiresAt'], requiresExpiry, errors, context);
}

Map<String, dynamic>? _readJsonObject(
  File file,
  List<String> errors,
  String label,
) {
  if (!file.existsSync()) {
    errors.add('缺少 $label：${_normalizePath(file.path)}');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      errors.add('$label 根节点必须是对象');
      return null;
    }
    return decoded;
  } on FormatException catch (error) {
    errors.add('$label 不是合法 JSON：${error.message}');
  } on FileSystemException catch (error) {
    errors.add('无法读取 $label：${error.message}');
  }
  return null;
}

void _validateKnownFields(
  Map<String, dynamic> object,
  Set<String> allowed,
  List<String> errors,
  String context,
) {
  for (final field in object.keys) {
    if (!allowed.contains(field)) {
      errors.add('$context 包含 schema 未定义字段：$field');
    }
  }
}

String? _requiredString(
  Map<String, dynamic> object,
  String field,
  List<String> errors,
  String context,
) {
  final value = object[field];
  if (value is! String || value.trim().isEmpty) {
    errors.add('$context 缺少非空 $field');
    return null;
  }
  return value.trim();
}

List<String> _requiredStringList(
  Map<String, dynamic> object,
  String field,
  List<String> errors,
  String context, {
  bool allowEmpty = false,
}) {
  final value = object[field];
  if (value is! List) {
    errors.add('$context 的 $field 必须是字符串数组');
    return const [];
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String || item.trim().isEmpty) {
      errors.add('$context 的 $field[$index] 必须是非空字符串');
    } else {
      result.add(item.trim());
    }
  }
  if (!allowEmpty && result.isEmpty) {
    errors.add('$context 的 $field 不能为空');
  }
  return result;
}

String? _validateEnumField(
  Map<String, dynamic> object,
  String field,
  Set<String> allowed,
  List<String> errors,
  String context,
) {
  final value = _requiredString(object, field, errors, context);
  if (value != null && !allowed.contains(value)) {
    errors.add('$context 的 $field 使用未知值 `$value`，允许值：${allowed.join(', ')}');
    return null;
  }
  return value;
}

Iterable<File> _sourceFiles(List<String> roots, Set<String> extensions) sync* {
  for (final rootPath in roots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || _isIgnoredPath(entity.path)) continue;
      final lowerPath = entity.path.toLowerCase();
      if (extensions.any(lowerPath.endsWith)) yield entity;
    }
  }
}

bool _isIgnoredPath(String path) {
  final segments = _normalizePath(path)
      .split('/')
      .map((part) => part.toLowerCase());
  return segments.any(
    const {
      'build',
      '.dart_tool',
      '.gradle',
      '.symlinks',
      '.plugin_symlinks',
      'pods',
      'deriveddata',
    }.contains,
  );
}

bool _isRuntimeDartPath(String path) =>
    path.contains('/lib/') || path.contains('/bin/');

String? _readSource(File file, List<String> errors) {
  try {
    return file.readAsStringSync();
  } on FileSystemException catch (error) {
    errors.add('无法读取源码 ${_normalizePath(file.path)}：${error.message}');
    return null;
  }
}

bool _plistBooleanEnabled(String source, String key) => RegExp(
  '<key>\\s*$key\\s*</key>\\s*<true\\s*/>',
  caseSensitive: false,
).hasMatch(source);

bool _containsAlwaysTrueBadCertificateCallback(String source) {
  final arrow = RegExp(
    r'''badCertificateCallback\s*=\s*\([^;{}]*\)\s*=>\s*true\s*;''',
    caseSensitive: false,
  );
  final block = RegExp(
    r'''badCertificateCallback\s*=\s*\([^;{}]*\)\s*\{\s*return\s+true\s*;\s*\}\s*;?''',
    caseSensitive: false,
  );
  return arrow.hasMatch(source) || block.hasMatch(source);
}

bool _containsUnconditionalServerTrustProceed(String source) {
  final arrow = RegExp(
    r'''onReceivedServerTrustAuthRequest\s*:\s*\([^;{}]*\)\s*(?:async\s*)?=>\s*ServerTrustAuthResponse\s*\([^;{}]*ServerTrustAuthResponseAction\s*\.\s*PROCEED[^;{}]*\)\s*,?''',
    caseSensitive: false,
  );
  final block = RegExp(
    r'''onReceivedServerTrustAuthRequest\s*:\s*\([^;{}]*\)\s*(?:async\s*)?\{\s*return\s+ServerTrustAuthResponse\s*\([^;{}]*ServerTrustAuthResponseAction\s*\.\s*PROCEED[^;{}]*\)\s*;\s*\}''',
    caseSensitive: false,
  );
  return arrow.hasMatch(source) || block.hasMatch(source);
}

bool _containsUnconditionalNativeSslProceed(String source) => RegExp(
  r'''onReceivedSslError\s*\([^{}]*\)\s*\{\s*(?:[A-Za-z_]\w*\s*\.\s*)?proceed\s*\(\s*\)\s*;?\s*\}''',
  caseSensitive: false,
).hasMatch(source);

bool _containsAlwaysTrueHostnameVerifier(String source) {
  final verifierBlock = RegExp(
    r'''HostnameVerifier[\s\S]{0,300}?verify\s*\([^{}]*\)\s*\{\s*return\s+true\s*;\s*\}''',
    caseSensitive: false,
  );
  final setter = RegExp(
    r'''setHostnameVerifier\s*\(\s*(?:\([^()]*\)|[^(){};]*)\s*(?:=>|->)\s*true\s*\)''',
    caseSensitive: false,
  );
  return verifierBlock.hasMatch(source) || setter.hasMatch(source);
}

void _validateFileHash(
  String path,
  String expectedHash,
  List<String> errors,
  String context,
) {
  if (!_isSafeRepoRelativePath(path)) {
    errors.add('$context 文件必须使用仓库内相对路径：$path');
    return;
  }
  if (!RegExp(r'''^[a-fA-F0-9]{64}$''').hasMatch(expectedHash)) {
    errors.add('$context SHA-256 必须是 64 位十六进制字符串');
    return;
  }
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$context 文件不存在：$path');
    return;
  }
  try {
    final actual = sha256.convert(file.readAsBytesSync()).toString();
    if (actual != expectedHash.toLowerCase()) {
      errors.add('$context SHA-256 不匹配：声明 $expectedHash，实际 $actual');
    }
  } on FileSystemException catch (error) {
    errors.add('$context 文件无法读取：${error.message}');
  }
}

void _validateOpenApiJson(File file, List<String> errors, String context) {
  if (!file.existsSync()) return;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic> ||
        (decoded['openapi'] is! String && decoded['swagger'] is! String)) {
      errors.add('$context JSON 必须包含 openapi 或 swagger 版本字段');
    }
  } on FormatException catch (error) {
    errors.add('$context 不是合法 JSON：${error.message}');
  } on FileSystemException catch (error) {
    errors.add('$context 无法读取：${error.message}');
  }
}

void _validateExistingRepoPath(
  String path,
  List<String> errors,
  String context,
) {
  if (!_isSafeRepoRelativePath(path)) {
    errors.add('$context 必须是仓库内相对路径：$path');
    return;
  }
  if (!File(path).existsSync() && !Directory(path).existsSync()) {
    errors.add('$context 不存在：$path');
  }
}

void _validateEvidence(String evidence, List<String> errors, String context) {
  if (_isAbsoluteHttpUrl(evidence)) {
    if (_hasUriUserInfo(evidence)) {
      errors.add('$context 的远程 evidence 不能包含用户名或密码：$evidence');
    }
    if (!evidence.startsWith('https://')) {
      errors.add('$context 的远程 evidence 必须使用 HTTPS：$evidence');
    }
    if (_hasUriQueryOrFragment(evidence)) {
      errors.add('$context 的远程 evidence 不能包含 query 或 fragment：$evidence');
    }
    return;
  }
  _validateExistingRepoPath(evidence, errors, '$context evidence');
}

void _validateExpiry(
  Object? raw,
  bool required,
  List<String> errors,
  String context,
) {
  if (raw == null) {
    if (required) errors.add('$context 必须提供 expiresAt');
    return;
  }
  if (raw is! String || raw.trim().isEmpty) {
    errors.add('$context 的 expiresAt 必须是 ISO-8601 日期或 null');
    return;
  }
  final expiry = DateTime.tryParse(raw);
  if (expiry == null) {
    errors.add('$context 的 expiresAt 不是合法 ISO-8601 日期：$raw');
    return;
  }
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final expiryDay = DateTime.utc(expiry.year, expiry.month, expiry.day);
  if (expiryDay.isBefore(today)) {
    errors.add('$context 的 expiresAt 已过期：$raw');
  }
}

bool _isAbsoluteHttpUrl(String raw) {
  final uri = Uri.tryParse(raw);
  return uri != null &&
      uri.isAbsolute &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

bool _hasUriUserInfo(String raw) {
  final uri = Uri.tryParse(raw);
  return uri != null && uri.userInfo.isNotEmpty;
}

bool _hasUriQueryOrFragment(String raw) {
  final uri = Uri.tryParse(raw);
  return uri != null && (uri.hasQuery || uri.hasFragment);
}

bool _isReservedTemplateHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == 'example.com' ||
      normalized.endsWith('.example.com') ||
      normalized == 'example.net' ||
      normalized.endsWith('.example.net') ||
      normalized == 'example.org' ||
      normalized.endsWith('.example.org') ||
      normalized.endsWith('.example') ||
      normalized.endsWith('.test') ||
      normalized.endsWith('.invalid');
}

bool _isAbsoluteSourceUri(String raw) {
  final uri = Uri.tryParse(raw);
  return uri != null && uri.isAbsolute && uri.scheme.isNotEmpty;
}

bool _isSafeRepoRelativePath(String path) {
  final normalized = _normalizePath(path);
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'''^[a-zA-Z]:/''').hasMatch(normalized)) {
    return false;
  }
  return !normalized.split('/').contains('..');
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

String _normalizeRepoPath(String path) {
  final normalized = _normalizePath(path);
  final root = _normalizePath(Directory.current.absolute.path);
  if (normalized.startsWith('$root/')) {
    return normalized.substring(root.length + 1);
  }
  return normalized.replaceFirst(RegExp(r'''^\./'''), '');
}

String _normalizePathSegment(String segment) => segment.trim().toLowerCase();

File _resolveRelativeTo(File owner, String relativePath) {
  if (!_isSafeRepoRelativePath(relativePath)) return File(relativePath);
  final ownerPath = _normalizePath(owner.path);
  final slash = ownerPath.lastIndexOf('/');
  final directory = slash < 0 ? '' : ownerPath.substring(0, slash + 1);
  return File('$directory$relativePath');
}

bool _looksLikePlaceholder(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('replace') ||
      normalized.contains('todo') ||
      normalized.contains('unknown') ||
      normalized.contains('<') ||
      normalized.contains('>');
}

void _rejectPlaceholder(String value, List<String> errors, String context) {
  if (_looksLikePlaceholder(value)) {
    errors.add('$context 在 template=false 时不能包含占位文本：$value');
  }
}

final class _OpenApiProvenanceBinding {
  const _OpenApiProvenanceBinding({
    required this.id,
    required this.inputFile,
    required this.configFile,
    required this.outputPackage,
  });

  final String id;
  final String inputFile;
  final String configFile;
  final String outputPackage;
}

final class _EgressManifest {
  const _EgressManifest({
    required this.template,
    required this.project,
    required this.declaredOrigins,
    required this.presentationPathSegments,
    required this.forbiddenSymbols,
    required this.transportConstructionPaths,
    required this.migration,
    required this.nativeSecurityExceptions,
  });

  factory _EgressManifest.fallback() => _EgressManifest(
    template: false,
    project: '',
    declaredOrigins: const {},
    presentationPathSegments: const {'presentation', 'page', 'pages'},
    forbiddenSymbols: const {},
    transportConstructionPaths: const {},
    migration: _MigrationConfig.disabled(),
    nativeSecurityExceptions: const {},
  );

  final bool template;
  final String project;
  final Set<String> declaredOrigins;
  final Set<String> presentationPathSegments;
  final Set<String> forbiddenSymbols;
  final Set<String> transportConstructionPaths;
  final _MigrationConfig migration;
  final Map<String, _NativeSecurityException> nativeSecurityExceptions;
}

final class _NativeSecurityException {
  const _NativeSecurityException({
    required this.kind,
    required this.path,
    required this.configSha256,
  });

  final String kind;
  final String path;
  final String configSha256;
}

final class _MigrationConfig {
  const _MigrationConfig({
    required this.enabled,
    required this.manifestPath,
    required this.requireZeroLegacy,
    required this.defaultStack,
  });

  factory _MigrationConfig.disabled() => const _MigrationConfig(
    enabled: false,
    manifestPath: 'tool/network/migration_manifest.json',
    requireZeroLegacy: false,
    defaultStack: 'legacy',
  );

  final bool enabled;
  final String manifestPath;
  final bool requireZeroLegacy;
  final String defaultStack;
}
