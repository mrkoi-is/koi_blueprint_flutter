import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/images/data/image_repository.dart';
import 'package:network_lab/features/images/data/image_validator.dart';
import 'package:network_lab/features/images/data/local_reader.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

import '../support/fixture_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('NETWORK_FIXTURE_URL');
  group(
    'owned real image HTTP fixture',
    () {
      late HttpTransport transport;
      late Uri base;
      setUp(() {
        transport = createFixtureHttpTransport();
        base = Uri.parse(endpoint);
      });
      tearDown(() => transport.close());
      test('real native/browser image HTTP decodes, cache survives offline, and 403/404/corruption fail', () async {
        final repository = ImageRepositoryImpl(
          transport: transport,
          localReader: createLocalImageReader(),
          assetReader: (_) async => throw StateError('unused'),
          validator: const FlutterImageValidator(),
        );
        final source = NetworkImageSource(base.resolve('image'));
        final image = await repository.load(
          source,
          cancellation: Cancellation(),
        );
        expect(image.bytes, isNotEmpty);
        for (final mode in ['403', '404', 'corrupt']) {
          await expectLater(
            repository.load(
              NetworkImageSource(base.resolve('image?mode=$mode')),
              cancellation: Cancellation(),
            ),
            throwsA(anything),
          );
        }
        await transport.close();
        expect(
          (await repository.load(
            source,
            cancellation: Cancellation(),
          )).fromCache,
          true,
        );
        repository.clear();
        await expectLater(
          repository.load(source, cancellation: Cancellation()),
          throwsStateError,
        );
        await repository.close();
      });
    },
    skip: endpoint.isEmpty
        ? 'Run tool/run_http_smoke.py for owned HTTP evidence'
        : false,
  );
}
