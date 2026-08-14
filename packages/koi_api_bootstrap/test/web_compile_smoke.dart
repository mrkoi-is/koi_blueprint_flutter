import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';

Future<void> main() async {
  final session = KoiMemoryTokenSession(initialToken: 'web-token');
  final runtime = await bootstrapKoiApi(
    const KoiApiBootstrapOptions(
      baseUrl: 'https://example.com/',
      environment: 'web',
    ),
    bindings: KoiApiBindings(tokenStorage: session),
  );

  if (!runtime.isNoop || runtime.backend != KoiApiBackend.webNoop) {
    throw StateError('Web must use the explicit no-op API runtime');
  }
  await runtime.dispose();
}
