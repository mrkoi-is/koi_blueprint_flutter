class KoiApiBootstrapOptions {
  const KoiApiBootstrapOptions({
    required this.baseUrl,
    required this.environment,
    this.enableLogging = false,
    this.enableInternalLogging = false,
    this.validateCertificate = true,
    this.enableProactiveTokenRefresh = false,
    this.tokenRefreshWhiteList = const [],
  });

  final String baseUrl;
  final String environment;

  /// 是否在原生网络后端记录请求与响应日志。
  ///
  /// 默认关闭，因为当前网络实现会记录请求正文，且没有公开的脱敏接口。
  final bool enableLogging;

  /// 是否通过已配置的日志回调输出诊断信息。
  final bool enableInternalLogging;

  /// 控制生产环境以外是否验证证书。
  ///
  /// 即使此值为 `false`，生产环境仍始终验证证书。
  final bool validateCertificate;

  /// 在接入真实令牌刷新实现之前保持关闭。
  final bool enableProactiveTokenRefresh;
  final List<String> tokenRefreshWhiteList;

  bool get isProduction {
    final normalized = environment.trim().toLowerCase();
    return normalized == 'prod' || normalized == 'production';
  }
}
