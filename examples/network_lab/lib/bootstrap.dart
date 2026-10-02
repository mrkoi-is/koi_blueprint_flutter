import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:network_lab/core/router/app_routes.dart';
import 'package:network_lab/features/network/application/network_session.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/data/http_transport.dart';
import 'package:network_lab/features/network/data/search_repository.dart';
import 'package:network_lab/features/network/data/transfer_store.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';
import 'package:network_lab/features/network/presentation/providers/network_providers.dart';

final class NetworkBootstrap {
  NetworkBootstrap._(
    this.transport,
    this.store,
    this.session,
    this.container,
    this.router,
  );
  final HttpTransport transport;
  final TransferStore store;
  final NetworkSession session;
  final ProviderContainer container;
  final GoRouter router;
  Future<void>? _closing;
  static Future<NetworkBootstrap> create({
    required Uri baseUri,
    String? nativeDirectory,
    String databaseName = 'koi_network_lab',
    HttpTransport Function()? transportFactory,
    Future<TransferStore> Function()? storeFactory,
  }) async {
    if (!['http', 'https'].contains(baseUri.scheme) || baseUri.host.isEmpty) {
      throw ArgumentError('HTTP base URI required');
    }
    final transport = (transportFactory ?? createHttpTransport)();
    TransferStore? store;
    try {
      store =
          await (storeFactory?.call() ??
              openTransferStore(
                nativeDirectory: nativeDirectory,
                databaseName: databaseName,
              ));
      final session = NetworkSession(
        repository: HttpSearchRepository(transport, baseUri),
        transfers: TransferEngine(transport, store),
        transport: transport,
        baseUri: baseUri,
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [networkSessionProvider.overrideWithValue(session)],
      );
      final router = GoRouter(routes: $appRoutes);
      return NetworkBootstrap._(transport, store, session, container, router);
    } catch (_) {
      await store?.close();
      await transport.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    router.dispose();
    container.dispose();
    try {
      await session.close();
    } finally {
      try {
        await store.close();
      } finally {
        await transport.close();
      }
    }
  }
}
