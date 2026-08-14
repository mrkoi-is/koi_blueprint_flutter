class KoiApiBootstrapOptions {
  const KoiApiBootstrapOptions({
    required this.baseUrl,
    required this.environment,
    this.enableLogging = false,
    this.enableInternalLogging = false,
    this.validateCertificate = true,
    this.enableProactiveTokenRefresh = true,
    this.tokenRefreshWhiteList = const [],
  });

  final String baseUrl;
  final String environment;

  /// Enables request and response logging in the native network backend.
  ///
  /// Disabled by default because the locked network implementation logs request
  /// bodies without a public redaction hook.
  final bool enableLogging;

  /// Enables diagnostic messages emitted through the configured log callback.
  final bool enableInternalLogging;

  /// Controls certificate validation outside production.
  ///
  /// Production always validates certificates even when this is false.
  final bool validateCertificate;

  final bool enableProactiveTokenRefresh;
  final List<String> tokenRefreshWhiteList;

  bool get isProduction {
    final normalized = environment.trim().toLowerCase();
    return normalized == 'prod' || normalized == 'production';
  }
}
