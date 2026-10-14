/// 显式选择运行环境；Release 构建不意味着连接生产后端。
enum KoiAppEnvironment { development, testing, staging, production }

/// 与主后端共用认证会话、编码器和网络策略的附加后端。
///
/// 这里只声明传输无关的地址与用途；不支持独立 token 或 adapter profile。
final class KoiBackendDefinition {
  const KoiBackendDefinition({
    required this.key,
    required this.purpose,
    required this.baseUrl,
  });

  final String key;
  final String purpose;
  final String baseUrl;
}

class KoiApiBootstrapOptions {
  const KoiApiBootstrapOptions({
    required this.baseUrl,
    required this.environment,
    this.primaryBackendKey = 'main',
    this.additionalBackends = const [],
    this.enableLogging = false,
    this.enableInternalLogging = false,
    this.validateCertificate = true,
    this.enableProactiveTokenRefresh = false,
    this.tokenRefreshWhiteList = const [],
  });

  final String baseUrl;

  /// dev/development、test/testing、staging、prod/production。
  ///
  /// 未知环境拒绝启动，避免拼写错误绕过生产约束。
  final String environment;

  /// 主后端的业务名称，原生实现将其映射到保留的 main module。
  final String primaryBackendKey;
  final List<KoiBackendDefinition> additionalBackends;

  /// 是否在原生网络后端记录原始请求与响应；生产环境禁止开启。
  final bool enableLogging;

  /// 是否输出底层诊断日志；其中可能包含请求数据，生产环境禁止开启。
  final bool enableInternalLogging;

  /// staging 和 production 始终验证证书，其他环境使用此值。
  final bool validateCertificate;

  /// 在接入真实令牌刷新实现之前保持关闭。
  final bool enableProactiveTokenRefresh;
  final List<String> tokenRefreshWhiteList;

  KoiAppEnvironment get appEnvironment =>
      switch (environment.trim().toLowerCase()) {
        'dev' || 'development' => KoiAppEnvironment.development,
        'test' || 'testing' => KoiAppEnvironment.testing,
        'staging' => KoiAppEnvironment.staging,
        'prod' || 'production' => KoiAppEnvironment.production,
        _ => throw ArgumentError.value(environment, 'environment', '未知运行环境'),
      };

  bool get isProduction => appEnvironment == KoiAppEnvironment.production;

  bool get requiresSecureTransport =>
      appEnvironment == KoiAppEnvironment.staging || isProduction;

  /// 验证全部配置并建立快照，必须在替换活动 Runtime 前调用。
  List<KoiBackendDefinition> validatedBackends() {
    final secureTransport = requiresSecureTransport;
    if (isProduction && (enableLogging || enableInternalLogging)) {
      throw StateError('production 禁止开启原始网络日志或内部诊断日志');
    }

    final backends = List<KoiBackendDefinition>.unmodifiable([
      KoiBackendDefinition(
        key: primaryBackendKey,
        purpose: 'Primary API',
        baseUrl: baseUrl,
      ),
      ...additionalBackends,
    ]);
    final keys = <String>{};
    for (final backend in backends) {
      if (backend.key.isEmpty || backend.key.trim() != backend.key) {
        throw ArgumentError.value(backend.key, 'key', '后端 key 不能为空或含首尾空格');
      }
      if (backend.key == 'token' ||
          (backend.key == 'main' && backend.key != primaryBackendKey)) {
        throw ArgumentError.value(backend.key, 'key', '后端 key 与保留 module 冲突');
      }
      if (!keys.add(backend.key)) {
        throw ArgumentError.value(backend.key, 'key', '后端 key 不能重复');
      }
      if (backend.purpose.trim().isEmpty) {
        throw ArgumentError.value(backend.purpose, 'purpose', '后端用途不能为空');
      }
      final uri = Uri.tryParse(backend.baseUrl);
      if (backend.baseUrl.trim() != backend.baseUrl ||
          uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw ArgumentError.value(
          backend.baseUrl,
          'baseUrl',
          '必须为不含凭据、query 或 fragment 的绝对 HTTP(S) URL',
        );
      }
      if (secureTransport && uri.scheme != 'https') {
        throw StateError('staging/production 后端必须使用 HTTPS：${backend.key}');
      }
    }
    return backends;
  }
}
