import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/data/transfer_store_stub.dart'
    as transfer;
import 'package:network_lab/shared/network/http_transport_stub.dart' as http;

void main() {
  test('unsupported HTTP platform explicitly rejects transport creation', () {
    expect(http.createHttpTransport, throwsUnsupportedError);
  });

  test(
    'unsupported storage rejects configuration instead of silently persisting',
    () {
      expect(
        () => transfer.openTransferStore(
          nativeDirectory: '/unused-on-unsupported-platform',
          databaseName: 'unsupported_test',
        ),
        throwsUnsupportedError,
      );
    },
  );
}
