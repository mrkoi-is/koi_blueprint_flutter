import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';

Future<void> main() async {
  final session = KoiMemoryTokenSession(initialToken: 'web-token');
  final runtime = await bootstrapKoiApi(
    const KoiApiBootstrapOptions(
      baseUrl: 'https://example.com/',
      environment: 'production',
      primaryBackendKey: 'account',
      additionalBackends: [
        KoiBackendDefinition(
          key: 'reporting',
          purpose: 'Reports',
          baseUrl: 'https://reports.example.com/',
        ),
      ],
    ),
    bindings: KoiApiBindings(tokenStorage: session),
  );

  if (!runtime.isNoop || runtime.backend != KoiApiBackend.webNoop) {
    throw StateError('Web must use the explicit no-op API runtime');
  }
  if (runtime.backendKeys.length != 2 ||
      !runtime.backendKeys.contains('reporting')) {
    throw StateError('Web no-op must retain the declared backend names');
  }
  await runtime.dispose();
}
