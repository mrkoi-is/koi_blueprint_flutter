import 'package:flutter_test/flutter_test.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_api_bootstrap/src/backend/web_backend.dart' as web;

void main() {
  test(
    'normalizes explicit environment aliases without build-mode inference',
    () {
      for (final entry in {
        'dev': KoiAppEnvironment.development,
        'development': KoiAppEnvironment.development,
        'test': KoiAppEnvironment.testing,
        'testing': KoiAppEnvironment.testing,
        'staging': KoiAppEnvironment.staging,
        'prod': KoiAppEnvironment.production,
        ' PRODUCTION ': KoiAppEnvironment.production,
      }.entries) {
        final options = KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/api/',
          environment: entry.key,
        );
        expect(options.appEnvironment, entry.value);
        expect(options.validatedBackends().single.baseUrl, options.baseUrl);
      }
      expect(
        () => const KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: 'prdo',
        ).validatedBackends(),
        throwsArgumentError,
      );
    },
  );

  test('rejects malformed or credential-bearing API URLs', () {
    for (final url in [
      '',
      '/api/',
      'ftp://example.com/',
      'https:///api/',
      'https://user:password@example.com/',
      'https://example.com/?token=secret',
      'https://example.com/?',
      'https://example.com/#fragment',
      ' https://example.com/',
    ]) {
      expect(
        () => KoiApiBootstrapOptions(
          baseUrl: url,
          environment: 'test',
        ).validatedBackends(),
        throwsArgumentError,
        reason: url,
      );
    }
  });

  test('staging and production reject HTTP on every backend', () {
    for (final environment in ['staging', 'production']) {
      expect(
        () => KoiApiBootstrapOptions(
          baseUrl: 'http://example.com/',
          environment: environment,
        ).validatedBackends(),
        throwsStateError,
      );
      expect(
        () => KoiApiBootstrapOptions(
          baseUrl: 'https://example.com/',
          environment: environment,
          additionalBackends: const [
            KoiBackendDefinition(
              key: 'reporting',
              purpose: 'Report service',
              baseUrl: 'http://reports.example.com/',
            ),
          ],
        ).validatedBackends(),
        throwsStateError,
      );
    }
  });

  test('production rejects raw and internal logging independently', () {
    for (final options in [
      const KoiApiBootstrapOptions(
        baseUrl: 'https://example.com/',
        environment: 'prod',
        enableLogging: true,
      ),
      const KoiApiBootstrapOptions(
        baseUrl: 'https://example.com/',
        environment: 'production',
        enableInternalLogging: true,
      ),
    ]) {
      expect(options.validatedBackends, throwsStateError);
    }
  });

  test('rejects colliding, reserved or undocumented backend definitions', () {
    for (final definition in [
      const KoiBackendDefinition(
        key: '',
        purpose: 'API',
        baseUrl: 'https://b.co/',
      ),
      const KoiBackendDefinition(
        key: ' bad',
        purpose: 'API',
        baseUrl: 'https://b.co/',
      ),
      const KoiBackendDefinition(
        key: 'token',
        purpose: 'API',
        baseUrl: 'https://b.co/',
      ),
      const KoiBackendDefinition(
        key: 'main',
        purpose: 'API',
        baseUrl: 'https://b.co/',
      ),
      const KoiBackendDefinition(
        key: 'primary',
        purpose: 'API',
        baseUrl: 'https://b.co/',
      ),
      const KoiBackendDefinition(
        key: 'reporting',
        purpose: ' ',
        baseUrl: 'https://b.co/',
      ),
    ]) {
      expect(
        () => KoiApiBootstrapOptions(
          baseUrl: 'https://a.co/',
          environment: 'test',
          primaryBackendKey: 'primary',
          additionalBackends: [definition],
        ).validatedBackends(),
        throwsArgumentError,
      );
    }
    expect(
      () => const KoiApiBootstrapOptions(
        baseUrl: 'https://a.co/',
        environment: 'test',
        primaryBackendKey: 'token',
      ).validatedBackends(),
      throwsArgumentError,
    );
  });

  test(
    'web runtime validates definitions and remains explicitly no-op',
    () async {
      addTearDown(web.disposeKoiApiBackend);
      final bindings = KoiApiBindings();
      final runtime = await web.bootstrapKoiApiBackend(
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
        bindings,
      );
      expect(runtime.bindings, same(bindings));
      expect(runtime.backendKeys, {'account', 'reporting'});
      expect(runtime.isNoop, isTrue);
      expect(runtime.backend, KoiApiBackend.webNoop);
      expect(() => runtime.backendKeys.add('other'), throwsUnsupportedError);
      await expectLater(
        web.bootstrapKoiApiBackend(
          const KoiApiBootstrapOptions(
            baseUrl: 'http://example.com/',
            environment: 'production',
          ),
          bindings,
        ),
        throwsStateError,
      );
      await runtime.dispose();
      await runtime.dispose();
    },
  );
}
