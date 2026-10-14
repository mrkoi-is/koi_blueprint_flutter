import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:json_schema/json_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../validate_network_architecture.dart' as network;

void main() {
  test(
    'Windows parser paths remain local and containment respects boundaries',
    () {
      for (final path in [r'C:\Repo\Spec.json', 'c:/Repo/Spec.json']) {
        expect(network.isLocalOpenApiPath(path, windows: true), isTrue);
      }
      for (final path in [
        'https://api.example.com/spec.json',
        'file:///C:/spec.json',
        'C:spec.json',
      ]) {
        expect(network.isLocalOpenApiPath(path, windows: true), isFalse);
      }
      expect(network.isLocalOpenApiPath('tool/openapi/spec.json'), isTrue);
      expect(
        network.canonicalRepoRelativePath(
          r'c:\REPO\Tool\Spec.json',
          r'C:\Repo',
          windows: true,
        ),
        'Tool/Spec.json',
      );
      expect(
        network.canonicalRepoRelativePath(
          'C:/Repo-other/spec.json',
          'c:/Repo',
          windows: true,
        ),
        isNull,
      );
      expect(
        network.canonicalRepoRelativePath(
          'D:/Repo/spec.json',
          'c:/Repo',
          windows: true,
        ),
        isNull,
      );
      expect(
        network.canonicalRepoRelativePath(
          r'\\server\share\Repo\Spec.json',
          r'\\SERVER\SHARE\repo',
          windows: true,
        ),
        'Spec.json',
      );
      expect(
        network.canonicalRepoRelativePath(
          '/Repo/Spec.json',
          '/repo',
          windows: false,
        ),
        isNull,
      );
    },
  );

  late Directory repositoryRoot;
  late File validator;
  late String packageConfig;
  late JsonSchema egressSchema;
  late JsonSchema migrationSchema;

  setUpAll(() {
    repositoryRoot = Directory.current.absolute;
    validator = File(
      '${repositoryRoot.path}/scripts/validate_network_architecture.dart',
    );
    packageConfig = '${repositoryRoot.path}/.dart_tool/package_config.json';
    expect(validator.existsSync(), isTrue, reason: '必须从仓库根目录运行测试');
    expect(File(packageConfig).existsSync(), isTrue, reason: '请先执行 pub get');
    egressSchema = JsonSchema.create(
      _readJson('tool/network/egress_manifest.schema.json'),
    );
    migrationSchema = JsonSchema.create(
      _readJson('tool/network/migration_manifest.schema.json'),
    );
  });

  group('网络清单 JSON Schema 回归', () {
    test('当前模板 egress manifest 符合 schema', () {
      _expectSchemaAccepted(
        egressSchema,
        _readJson('tool/network/egress_manifest.json'),
      );
    });

    test('离线清单与开发样例 schema 保持明确边界', () {
      final offline =
          _cloneJsonMap(_readJson('tool/network/egress_manifest.json'))
            ..['template'] = false
            ..['entries'] = <Object?>[];
      _expectSchemaAccepted(egressSchema, offline);

      final template = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      );
      final development = (template['entries']! as List).firstWhere(
        (entry) => (entry as Map)['developmentOnly'] == true,
      ) as Map;
      development['hosts'] = <String, Object?>{
        'development': 'http://127.0.0.1:8765/',
        'production': 'https://media.acme.cn/',
      };
      _expectSchemaRejected(egressSchema, template);
    });

    test('template=false 拒绝未替换的模板分类和保留域名', () {
      final manifest = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      )..['template'] = false;

      _expectSchemaRejected(egressSchema, manifest);
    });

    test('template=false 大小写变化也不能绕过示例保留域名', () {
      final manifest = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      )..['template'] = false;
      final entry = (manifest['entries']! as List).first as Map;
      manifest['entries'] = <Object?>[entry];
      entry['dataClassification'] = 'internal';
      final hosts = entry['hosts']! as Map;
      hosts['development'] = 'https://dev-api.acme.cn/';
      hosts['staging'] = 'https://staging-api.acme.cn/';
      hosts['production'] = 'https://API.EXAMPLE.COM/';

      _expectSchemaRejected(egressSchema, manifest);
    });

    test('egress schema 拒绝 evidence query 或 fragment', () {
      final manifest = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      );
      final entry = (manifest['entries']! as List).first as Map;
      entry['testEvidence'] = [
        'https://review.acme.cn/result?access_key=secret',
      ];

      _expectSchemaRejected(egressSchema, manifest);
    });

    test('platform SDK entry 示例与 provider_managed schema 保持一致', () {
      final manifest = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      );
      manifest['entries'] = <Object?>[
        _readJson('tool/network/egress_platform_sdk_entry.example.json'),
      ];

      _expectSchemaAccepted(egressSchema, manifest);
    });

    test('migration example 符合 schema', () {
      _expectSchemaAccepted(
        migrationSchema,
        _readJson('tool/network/migration_manifest.example.json'),
      );
    });

    test('启用迁移门禁后，实际 migration manifest 也必须符合 schema', () {
      final egress = _cloneJsonMap(
        _readJson('tool/network/egress_manifest.json'),
      );
      final migration = (egress['migration']! as Map).cast<String, Object?>();
      if (migration['enabled'] != true) return;

      _expectSchemaAccepted(
        migrationSchema,
        _readJson(migration['manifest']! as String),
      );
    });

    test('migration schema 拒绝占位 owner', () {
      final manifest = _cloneJsonMap(
        _readJson('tool/network/migration_manifest.example.json'),
      );
      final entry = (manifest['entries']! as List).first as Map;
      entry['owner'] = 'TODO';

      _expectSchemaRejected(migrationSchema, manifest);
    });
  });

  group('网络架构 validator 黑盒回归', () {
    test('最小 baseline 可以通过', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);

      final result = await fixture.runValidator(validator, packageConfig);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('基础 lint 通过'));
    });

    test('离线项目允许空出口清单，仍扫描未登记的 origin', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(template: false, entries: []);
      var result = await fixture.runValidator(validator, packageConfig);
      expect(result.exitCode, 0, reason: result.output);
      await fixture.writeFile(
        'examples/demo/lib/endpoint.dart',
        "const endpoint = 'https://undeclared.acme.cn/';",
      );
      result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: '网络 origin 未登记');
    });

    test('开发样例无需虚构 staging/production Host', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..['developmentOnly'] = true
        ..['securityPolicy'] = 'development_only'
        ..['hosts'] = <String, Object?>{'development': 'http://127.0.0.1:8765/'}
        ..['tls'] = <String, Object?>{};
      await fixture.writeManifest(entries: [entry]);
      _expectSchemaAccepted(
        egressSchema,
        _readJson('${fixture.root.path}/tool/network/egress_manifest.json'),
      );
      var result = await fixture.runValidator(validator, packageConfig);
      expect(result.exitCode, 0, reason: result.output);

      await fixture.writeManifest(template: false, entries: [entry]);
      _expectSchemaRejected(
        egressSchema,
        _readJson('${fixture.root.path}/tool/network/egress_manifest.json'),
      );
      result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'developmentOnly 仅可用于');
    });

    test('运行时 Host 样例不能冒充正式安全策略', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..['developmentOnly'] = true
        ..['securityPolicy'] = 'development_only'
        ..['dynamicUrlPolicy'] = 'runtime_supplied'
        ..['hostPolicy'] = 'runtime_supplied'
        ..['hosts'] = null
        ..['tls'] = null;
      await fixture.writeManifest(entries: [entry]);
      _expectSchemaAccepted(
        egressSchema,
        _readJson('${fixture.root.path}/tool/network/egress_manifest.json'),
      );
      var result = await fixture.runValidator(validator, packageConfig);
      expect(result.exitCode, 0, reason: result.output);

      entry['developmentOnly'] = false;
      entry['securityPolicy'] = 'strict_tls';
      await fixture.writeManifest(entries: [entry]);
      _expectSchemaRejected(
        egressSchema,
        _readJson('${fixture.root.path}/tool/network/egress_manifest.json'),
      );
      result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'runtime_supplied 仅用于');

      // A declared baseline host must not make an unvalidated dynamic policy
      // eligible for a non-template project either.
      final declared = fixture.baseEntry()
        ..['dynamicUrlPolicy'] = 'runtime_supplied';
      await fixture.writeManifest(template: false, entries: [declared]);
      _expectSchemaRejected(
        egressSchema,
        _readJson('${fixture.root.path}/tool/network/egress_manifest.json'),
      );
      result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'runtime_supplied URL 必须');
    });

    test('examples/modules 的 presentation 和 TLS 都必须扫描', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeFile(
        'examples/demo/lib/presentation/page.dart',
        "import 'package:dio/dio.dart';",
      );
      await fixture.writeFile(
        'modules/demo/lib/unsafe.dart',
        'void configure() { client.badCertificateCallback = (a, b, c) => true; }',
      );
      final result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'Presentation 不能导入 Dio');
      expect(result.output, contains('badCertificateCallback 无条件接受证书'));
    });

    test('transport 构造豁免仅作用于登记的精确文件', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const path = 'examples/demo/lib/shared/network/transport.dart';
      await fixture.writeFile(path, 'final client = Dio();');
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        transportConstructionPaths: [path],
      );
      var result = await fixture.runValidator(validator, packageConfig);
      expect(result.exitCode, 0, reason: result.output);
      await fixture.writeFile(
        'examples/demo/lib/shared/network/other.dart',
        'final other = Dio();',
      );
      result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'other.dart');
    });

    test('transport 构造豁免不绕过 presentation、TLS 与 origin', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const path = 'examples/demo/lib/presentation/transport.dart';
      await fixture.writeFile(
        path,
        "import 'package:dio/dio.dart';\n"
        'final dio = Dio();\n'
        "const endpoint = 'https://undeclared.acme.cn/';\n"
        'void configure() { client.badCertificateCallback = (a, b, c) => true; }',
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        transportConstructionPaths: [path],
      );
      final result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: 'Presentation 不能导入 Dio');
      expect(result.output, contains('badCertificateCallback 无条件接受证书'));
      expect(result.output, contains('网络 origin 未登记'));
    });

    test('transport 清单拒绝目录和不存在的路径', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        transportConstructionPaths: ['examples/demo/lib', '../transport.dart'],
      );
      final result = await fixture.runValidator(validator, packageConfig);
      _expectRejected(result, containsText: '必须是扫描范围内存在的 Dart 源文件');
    });

    test('拒绝 hosts 中未声明的环境 key', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry();
      (entry['hosts']! as Map<String, Object?>)['qa'] =
          'https://qa-api.example.com/';
      await fixture.writeManifest(entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(
        result,
        containsText: 'schema 未定义字段：qa',
        reason: '额外 hosts key 必须失败',
      );
    });

    test('拒绝 tls 中未声明的环境 key', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry();
      (entry['tls']! as Map<String, Object?>)['development'] = 'strict';
      await fixture.writeManifest(entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(
        result,
        containsText: 'schema 未定义字段：development',
        reason: '额外 tls key 必须失败',
      );
    });

    test('template=false 拒绝正式字段中的占位文本', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..['owner'] = 'apps/<app>/lib/core/network'
        ..['securityPolicyDetails'] = 'TODO replace with release policy';
      await fixture.writeManifest(template: false, entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '占位文本');
    });

    test('template=false 拒绝模板数据分类', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()..['dataClassification'] = 'template';
      await fixture.writeManifest(template: false, entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不能使用 template 数据分类');
    });

    test('template=false 拒绝示例保留域名', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry();
      (entry['hosts']! as Map<String, Object?>)['production'] =
          'https://api.example.com/';
      await fixture.writeManifest(template: false, entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不能使用示例保留域名');
    });

    test('拒绝远程 evidence URL 嵌入用户名或密码', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..['testEvidence'] = <Object?>[
          'https://reviewer:secret@review.example.com/network',
        ];
      await fixture.writeManifest(entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '远程 evidence 不能包含用户名或密码');
    });

    test('拒绝远程 evidence URL 中的 query 或 fragment', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..['testEvidence'] = <Object?>[
          'https://review.example.com/network?token=secret',
        ];
      await fixture.writeManifest(entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(
        result,
        containsText: '远程 evidence 不能包含 query 或 fragment',
      );
    });

    test('拒绝 prodRelease 等伪装成非生产的 native exception', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const configPath =
          'apps/test_app/android/app/src/prodRelease/res/xml/network_security_config.xml';
      await fixture.writeFile(
        configPath,
        '<network-security-config>'
        '<domain-config cleartextTrafficPermitted="true">'
        '<domain>dev.example.com</domain>'
        '</domain-config>'
        '</network-security-config>',
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        nativeSecurityExceptions: [
          await fixture.nativeException(
            path: configPath,
            sourceSet: 'prodRelease',
          ),
        ],
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不在已知非生产 allowlist');
    });

    test('拒绝已经过期的 native exception', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const configPath =
          'apps/test_app/android/app/src/dev/res/xml/network_security_config.xml';
      await fixture.writeFile(
        configPath,
        '<network-security-config>'
        '<domain-config cleartextTrafficPermitted="true">'
        '<domain>dev.example.com</domain>'
        '</domain-config>'
        '</network-security-config>',
      );
      final exception =
          await fixture.nativeException(path: configPath, sourceSet: 'dev')
            ..['expiresAt'] = '2000-01-01';
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        nativeSecurityExceptions: [exception],
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '已过期');
    });

    test('允许 dev domain-config 携带正确 SHA 的批准例外', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const configPath =
          'apps/test_app/android/app/src/dev/res/xml/network_security_config.xml';
      await fixture.writeFile(
        configPath,
        _domainCleartextConfig('dev.example.com'),
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        nativeSecurityExceptions: [
          await fixture.nativeException(path: configPath, sourceSet: 'dev'),
        ],
      );

      final result = await fixture.runValidator(validator, packageConfig);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('基础 lint 通过'));
    });

    test('dev domain-config 缺少批准例外也必须失败', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const configPath =
          'apps/test_app/android/app/src/dev/res/xml/network_security_config.xml';
      await fixture.writeFile(
        configPath,
        _domainCleartextConfig('dev.example.com'),
      );
      await fixture.writeManifest(entries: [fixture.baseEntry()]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '必须登记带期限、证据和配置 SHA-256');
    });

    test('配置文件在批准后被修改会因 SHA 不匹配而失败', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const configPath =
          'apps/test_app/android/app/src/dev/res/xml/network_security_config.xml';
      await fixture.writeFile(
        configPath,
        _domainCleartextConfig('dev.example.com'),
      );
      final exception = await fixture.nativeException(
        path: configPath,
        sourceSet: 'dev',
      );
      await fixture.writeFile(
        configPath,
        _domainCleartextConfig('changed.example.com'),
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        nativeSecurityExceptions: [exception],
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'SHA-256 不匹配');
    });

    test('允许 platform SDK 明确声明 provider_managed 且 Host 未知', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry()
        ..addAll({
          'id': 'vendor_sdk',
          'category': 'platform_sdk',
          'purpose': '厂商平台 SDK',
          'transport': 'platform_sdk',
          'contract': 'platform',
          'authentication': 'platform_sdk',
          'authFailurePolicy': 'plugin_managed',
          'retryPolicy': 'plugin_managed',
          'dynamicUrlPolicy': 'platform_managed',
          'hostPolicy': 'provider_managed',
          'securityPolicy': 'provider_managed',
          'securityPolicyDetails': '厂商负责 TLS、证书更新和安全响应',
          'provider': 'Example Vendor SDK',
          'hosts': null,
          'tls': null,
        });
      await fixture.writeManifest(template: false, entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('基础 lint 通过'));
    });

    test('拒绝无条件 badCertificateCallback 证书绕过', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeFile(
        'apps/test_app/lib/insecure_client.dart',
        'void configure(dynamic client) {\n'
            '  client.badCertificateCallback = '
            '(certificate, host, port) => true;\n'
            '}\n',
      );
      await fixture.writeManifest(entries: [fixture.baseEntry()]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'badCertificateCallback');
    });

    test('拒绝 declared Host 中的 query 或 fragment', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final entry = fixture.baseEntry();
      (entry['hosts']! as Map<String, Object?>)['development'] =
          'https://dev-api.example.com/base?token=secret';
      await fixture.writeManifest(entries: [entry]);

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'query 或 fragment');
    });

    test('拒绝 OpenAPI sourceUrl 嵌入用户名或密码', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://swagger:secret@api.example.com/swagger.json',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'sourceUrl 不能包含用户名或密码');
    });

    test('拒绝 OpenAPI sourceUrl 中的 query 或 fragment', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.example.com/swagger.json?api_key=secret',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'sourceUrl 不能包含 query 或 fragment');
    });

    test('OpenAPI provenance 与活动 parser 配置一致时通过', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('基础 lint 通过'));
    });

    test('活动 parser 配置存在但 provenance 缺失时拒绝', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeFile(
        'tool/koi_swagger_parser/orphan.yaml',
        'input:\n  swagger_urls:\n    - ../openapi/orphan.json\n',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(
        result,
        containsText: '活动 parser 配置未被 OpenAPI provenance 覆盖',
      );
    });

    test('example parser 配置不会被当作活动配置', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeFile(
        'tool/koi_swagger_parser/orphan.example.yaml',
        '这不是活动配置',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('基础 lint 通过'));
    });

    test('活动 parser input 与 provenance source 不一致时拒绝', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeFile(
        'tool/openapi/other.openapi.json',
        '{"openapi":"3.0.0","paths":{}}',
      );
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
        configSource: '../openapi/other.openapi.json',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '生成输入不在配置 enabled inputs 中');
    });

    test('活动 parser output 与 provenance package 不一致时拒绝', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
        configOutputPackage: 'other_api',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'outputPackage 与活动配置不一致');
    });

    test('provenance parserVersion 与 pubspec.lock 不一致时拒绝', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
        extraContractFields: const {'parserVersion': '9.9.9'},
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'parserVersion 与 pubspec.lock 不一致');
    });

    test('纯生成 API 包不能直接依赖 koi_network', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
      );
      await fixture.writeFile(
        'packages/test_api/pubspec.yaml',
        'name: test_api\n'
            'environment:\n  sdk: ^3.11.0\n'
            'dependencies:\n  koi_network: ^0.0.5\n',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '纯生成 API 包 packages/test_api 不能依赖');
    });

    test('纯生成 API 包不能重导出 koi_network', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
      );
      await fixture.writeFile(
        'packages/test_api/lib/test_api.dart',
        "export 'package:koi_network/koi_network.dart';\n",
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不能导入或重导出 koi_network');
    });

    test('template=false 拒绝 template_example OpenAPI provenance', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(
        template: false,
        entries: [fixture.baseEntry()],
      );
      await fixture.writeProvenance(
        sourceUrl: 'local-template://tool/openapi/test.openapi.json',
        extraContractFields: const {'authority': 'template_example'},
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不能使用 template_example authority');
    });

    test('template=false 拒绝 OpenAPI provenance 示例保留域名', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(
        template: false,
        entries: [fixture.baseEntry()],
      );
      await fixture.writeProvenance(
        sourceUrl: 'https://api.example.com/swagger.json',
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: '不能使用示例保留域名');
    });

    test('OpenAPI provenance 拒绝 schema 未声明字段', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
        extraContractFields: const {'swaggerPassword': 'secret'},
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'schema 未定义字段：swaggerPassword');
    });

    test('兼容 OpenAPI provenance 拒绝占位责任信息', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeManifest(entries: [fixture.baseEntry()]);
      await fixture.writeProvenance(
        sourceUrl: 'https://api.acme.cn/swagger.json',
        extraContractFields: const {
          'authority': 'compatibility',
          'compatibilityReason': 'TODO',
          'compatibilityOwner': 'network-team',
          'compatibilityRemoveWhen': '服务端发布权威 Swagger 后删除',
        },
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'compatibilityReason');
    });

    test('迁移清单拒绝 schema 未声明字段', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const consumer = 'apps/test_app/lib/features/example_repository.dart';
      await fixture.writeFile(consumer, '// fixture consumer\n');
      await fixture.writeMigrationManifest(
        entry: <String, Object?>{
          'backend': 'main',
          'method': 'GET',
          'path': '/api/v1/example',
          'uiReachable': true,
          'consumer': consumer,
          'currentStack': 'koi_generated',
          'targetStack': 'koi_generated',
          'status': 'migrated',
          'owner': 'test-network-team',
          'reason': '已完成生成客户端与消费者验证',
          'expiresAt': null,
          'evidence': <Object?>['evidence/network_contract_test.dart'],
          'stauts': 'migrated',
        },
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        migration: <String, Object?>{
          'enabled': true,
          'manifest': 'tool/network/migration_manifest.json',
          'requireZeroLegacy': false,
          'defaultStack': 'koi_generated',
        },
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(result, containsText: 'schema 未定义字段：stauts');
    });

    test('迁移清单拒绝占位原因', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const consumer = 'apps/test_app/lib/features/example_repository.dart';
      await fixture.writeFile(consumer, '// fixture consumer\n');
      await fixture.writeMigrationManifest(
        entry: <String, Object?>{
          'backend': 'main',
          'method': 'GET',
          'path': '/api/v1/example',
          'uiReachable': true,
          'consumer': consumer,
          'currentStack': 'legacy',
          'targetStack': 'koi_generated',
          'status': 'exception',
          'owner': 'test-network-team',
          'reason': 'TODO',
          'expiresAt': '2099-01-01',
          'evidence': <Object?>['evidence/network_contract_test.dart'],
        },
      );
      await fixture.writeManifest(
        entries: [fixture.baseEntry()],
        migration: <String, Object?>{
          'enabled': true,
          'manifest': 'tool/network/migration_manifest.json',
          'requireZeroLegacy': false,
          'defaultStack': 'koi_generated',
        },
      );

      final result = await fixture.runValidator(validator, packageConfig);

      _expectRejected(
        result,
        containsText: 'reason 在 template=false 时不能包含占位文本',
      );
    });
  });
}

Object _readJson(String path) {
  final value = jsonDecode(File(path).readAsStringSync());
  if (value == null) throw FormatException('$path 的 JSON 根节点不能是 null');
  return value as Object;
}

Map<String, Object?> _cloneJsonMap(Object? value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

void _expectSchemaAccepted(JsonSchema schema, Object? value) {
  final result = schema.validate(value, validateFormats: true);
  expect(result.isValid, isTrue, reason: result.errors.join('\n'));
}

void _expectSchemaRejected(JsonSchema schema, Object? value) {
  final result = schema.validate(value, validateFormats: true);
  expect(result.isValid, isFalse, reason: '该 fixture 应被 JSON Schema 拒绝');
}

String _domainCleartextConfig(String domain) =>
    '<network-security-config>'
    '<domain-config cleartextTrafficPermitted="true">'
    '<domain>$domain</domain>'
    '</domain-config>'
    '</network-security-config>';

void _expectRejected(
  _ValidatorResult result, {
  String? containsText,
  String? reason,
}) {
  final detail =
      '${reason ?? 'validator 应拒绝该 fixture'}，实际输出：\n${result.output}';
  expect(result.exitCode, isNot(0), reason: detail);
  expect(
    result.output,
    contains('网络架构基础 lint 失败'),
    reason: '编译错误或进程启动错误不能冒充预期拒绝。$detail',
  );
  if (containsText != null) {
    expect(result.output, contains(containsText), reason: detail);
  }
}

final class _Fixture {
  _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'koi_network_lint_test_',
    );
    final fixture = _Fixture(root);
    await fixture.writeFile(
      'evidence/network_contract_test.dart',
      '// fixture evidence\n',
    );
    return fixture;
  }

  Map<String, Object?> baseEntry() => <String, Object?>{
    'id': 'main_api',
    'category': 'business_api',
    'purpose': '测试业务 API',
    'owner': 'test-network-team',
    'dataClassification': 'internal',
    'transport': 'koi_network',
    'contract': 'openapi',
    'authentication': 'project_adapter',
    'authFailurePolicy': 'global_session',
    'retryPolicy': 'endpoint_semantics',
    'dynamicUrlPolicy': 'fixed_origin',
    'hostPolicy': 'declared',
    'securityPolicy': 'strict_tls',
    'securityPolicyDetails': 'staging 和 production 使用严格 TLS',
    'hosts': <String, Object?>{
      'development': 'https://dev-api.acme.cn/',
      'staging': 'https://staging-api.acme.cn/',
      'production': 'https://api.acme.cn/',
    },
    'tls': <String, Object?>{'staging': 'strict', 'production': 'strict'},
    'testEvidence': <Object?>['evidence/network_contract_test.dart'],
  };

  Future<Map<String, Object?>> nativeException({
    required String path,
    required String sourceSet,
  }) async {
    final config = File('${root.path}/$path');
    final configSha256 = sha256.convert(await config.readAsBytes()).toString();
    return <String, Object?>{
      'id': 'temporary_cleartext',
      'kind': 'android_domain_cleartext',
      'path': path,
      'sourceSet': sourceSet,
      'reason': '仅用于本地测试服务',
      'owner': 'test-network-team',
      'approvedBy': 'security-reviewer',
      'environments': <Object?>['development'],
      'expiresAt': '2099-01-01',
      'evidence': <Object?>['evidence/network_contract_test.dart'],
      'configSha256': configSha256,
    };
  }

  Future<void> writeManifest({
    bool template = true,
    required List<Map<String, Object?>> entries,
    List<Map<String, Object?>> nativeSecurityExceptions = const [],
    Map<String, Object?>? migration,
    List<String> transportConstructionPaths = const [],
  }) => writeFile(
    'tool/network/egress_manifest.json',
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schemaVersion': 1,
      'gateScope': 'basic_lint',
      'template': template,
      'project': 'validator_fixture',
      'boundaries': <String, Object?>{
        'presentationPathSegments': <Object?>['presentation'],
        'forbiddenSymbols': <Object?>[],
        'transportConstructionPaths': transportConstructionPaths,
      },
      'migration':
          migration ??
          <String, Object?>{
            'enabled': false,
            'manifest': 'tool/network/migration_manifest.json',
            'requireZeroLegacy': false,
            'defaultStack': 'koi_generated',
          },
      'nativeSecurityExceptions': nativeSecurityExceptions,
      'entries': entries,
    }),
  );

  Future<void> writeMigrationManifest({required Map<String, Object?> entry}) =>
      writeFile(
        'tool/network/migration_manifest.json',
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'schemaVersion': 1,
          'project': 'validator_fixture',
          'entries': <Object?>[entry],
        }),
      );

  Future<void> writeProvenance({
    required String sourceUrl,
    String configSource = '../openapi/test.openapi.json',
    String configOutputPackage = 'test_api',
    Map<String, Object?> extraContractFields = const {},
  }) async {
    const sourcePath = 'tool/openapi/test.openapi.json';
    const configPath = 'tool/koi_swagger_parser/test.yaml';
    await writeFile(sourcePath, '{"openapi":"3.0.0","paths":{}}');
    await writeFile(
      configPath,
      'input:\n'
      '  swagger_urls:\n'
      '    - url: $configSource\n'
      '      enabled: true\n'
      'output:\n'
      '  base_dir: ../../packages/$configOutputPackage/lib/src/koi_generated\n'
      '  api_dir: ../../packages/$configOutputPackage/lib/src/koi_generated/api\n'
      '  models_dir: ../../packages/$configOutputPackage/lib/src/koi_generated/api_models\n',
    );
    await writeFile(
      'packages/test_api/lib/test_api.dart',
      '// generated API\n',
    );
    await writeFile(
      'packages/test_api/pubspec.yaml',
      'name: test_api\nenvironment:\n  sdk: ^3.11.0\n',
    );
    if (configOutputPackage != 'test_api') {
      await writeFile(
        'packages/$configOutputPackage/pubspec.yaml',
        'name: $configOutputPackage\nenvironment:\n  sdk: ^3.11.0\n',
      );
      for (final directory in const [
        'lib/src/koi_generated/api',
        'lib/src/koi_generated/api_models',
      ]) {
        await writeFile('packages/$configOutputPackage/$directory/.keep', '');
      }
    }
    for (final directory in const [
      'lib/src/koi_generated/api',
      'lib/src/koi_generated/api_models',
    ]) {
      await writeFile('packages/test_api/$directory/.keep', '');
    }
    final sourceSha = sha256
        .convert(await File('${root.path}/$sourcePath').readAsBytes())
        .toString();
    final configSha = sha256
        .convert(await File('${root.path}/$configPath').readAsBytes())
        .toString();
    final contract = <String, Object?>{
      'id': 'test',
      'authority': 'server',
      'sourceUrl': sourceUrl,
      'fetchedAt': '2026-08-03T00:00:00Z',
      'sourceFile': sourcePath,
      'sourceSha256': sourceSha,
      'overlayFile': null,
      'overlaySha256': null,
      'parser': 'koi_swagger_parser',
      'parserVersion': '0.2.0',
      'configFile': configPath,
      'configSha256': configSha,
      'generationCommand': 'dart run generator',
      'outputPackage': 'packages/test_api',
      ...extraContractFields,
    };
    await writeFile(
      'tool/openapi/PROVENANCE.json',
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'contracts': <Object?>[contract],
      }),
    );
    await writeFile(
      'pubspec.lock',
      'packages:\n'
          '  koi_swagger_parser:\n'
          '    dependency: direct dev\n'
          '    description:\n'
          '      name: koi_swagger_parser\n'
          '    source: hosted\n'
          '    version: "0.2.0"\n',
    );
  }

  Future<void> writeFile(String relativePath, String contents) async {
    final file = File('${root.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<_ValidatorResult> runValidator(
    File validator,
    String packageConfig,
  ) async {
    final result = await Process.run(_dartExecutable(), [
      '--packages=$packageConfig',
      validator.path,
    ], workingDirectory: root.path);
    return _ValidatorResult(
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
    );
  }

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

final class _ValidatorResult {
  const _ValidatorResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

// flutter test runs in flutter_tester, while black-box validators are Dart CLIs.
String _dartExecutable() {
  final configured = Platform.environment['DART_BIN'];
  if (configured != null && configured.isNotEmpty) return configured;
  final executable = File(Platform.resolvedExecutable);
  if (executable.uri.pathSegments.last == 'dart' ||
      executable.uri.pathSegments.last == 'dart.exe') {
    return executable.path;
  }
  var directory = executable.parent;
  while (true) {
    final candidate = File(
      '${directory.path}/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Cannot locate Dart SDK; set DART_BIN for validator tests');
}
