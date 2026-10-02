import 'dart:io';

import 'package:network_lab/shared/network/domain/http_ports.dart';
import 'package:network_lab/shared/network/http_transport.dart';

/// Only this owned fixture's requests bypass Flutter's HTTP 400 test override.
/// Respect a host's existing binding and never change its global HttpOverrides.
HttpTransport createFixtureHttpTransport() => _FixtureTransport();

final class _RealClientOverrides extends HttpOverrides {}

final class _FixtureTransport implements HttpTransport {
  final _inner = createHttpTransport();

  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) => HttpOverrides.runWithHttpOverrides(
    () => _inner.open(
      uri,
      cancellation: cancellation,
      method: method,
      headers: headers,
    ),
    _RealClientOverrides(),
  );

  @override
  Future<void> close() => _inner.close();
}
