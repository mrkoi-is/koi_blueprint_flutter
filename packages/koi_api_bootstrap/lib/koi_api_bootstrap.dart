import 'package:koi_network/koi_network.dart';

class KoiApiBootstrapOptions {
  const KoiApiBootstrapOptions({
    required this.baseUrl,
    required this.environment,
    this.enableLogging = true,
  });

  final String baseUrl;
  final String environment;
  final bool enableLogging;
}

Future<void> bootstrapKoiApi(KoiApiBootstrapOptions options) async {
  KoiNetworkAdapters.register(
    authAdapter: KoiDefaultAuthAdapter(),
    errorHandlerAdapter: KoiDefaultErrorHandlerAdapter(),
    loadingAdapter: KoiDefaultLoadingAdapter(),
    platformAdapter: KoiDefaultPlatformAdapter(),
    loggerAdapter: KoiDefaultLoggerAdapter(),
    responseParser: const KoiDefaultResponseParser(),
    requestEncoder: const KoiJsonRequestEncoder(),
  );

  await KoiNetworkInitializer.initialize(
    baseUrl: options.baseUrl,
    environment: options.environment,
    enableLogging: options.enableLogging,
  );
}
