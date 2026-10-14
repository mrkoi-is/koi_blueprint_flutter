import 'dart:async';

import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart' show CapabilityLifecycle;
import 'package:network_lab/features/network/application/network_session.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/data/http_transport.dart';
import 'package:network_lab/features/network/data/search_repository.dart';
import 'package:network_lab/features/network/data/transfer_store.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';
import 'package:network_lab/features/network/presentation/providers/network_providers.dart';
import 'package:network_lab/features/network/presentation/screens/network_page.dart';

Widget buildNetworkCapabilityPage(BuildContext context) =>
    const NetworkCapabilityPage();

/// The host owns routing. This page owns and drains only its network resources.
class _InvalidEndpoint implements Exception {
  const _InvalidEndpoint();
}

class NetworkCapabilityPage extends StatefulWidget {
  const NetworkCapabilityPage({
    this.endpoint = const String.fromEnvironment('NETWORK_LAB_URL'),
    this.transportFactory,
    this.storeFactory,
    super.key,
  });
  final String endpoint;
  final HttpTransport Function()? transportFactory;
  final Future<TransferStore> Function()? storeFactory;
  @override
  State<NetworkCapabilityPage> createState() => _NetworkCapabilityPageState();
}

class _NetworkCapabilityPageState extends State<NetworkCapabilityPage> {
  NetworkSession? _session;
  TransferStore? _store;
  HttpTransport? _transport;
  Object? _error;
  bool _connecting = true;
  bool _editingEndpoint = false;
  late final _endpoint = TextEditingController(text: widget.endpoint);
  Future<void>? _opening;
  Future<void>? _closing;
  late final VoidCallback _unregister;

  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async => true,
      close: _close,
    );
    _opening = _open();
  }

  Future<void> _open() async {
    try {
      final uri = Uri.tryParse(_endpoint.text.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const _InvalidEndpoint();
      }
      await _release();
      final transport = _transport =
          (widget.transportFactory ?? createHttpTransport)();
      final store = _store =
          await (widget.storeFactory?.call() ??
              openTransferStore(databaseName: 'network_capability'));
      final session = NetworkSession(
        repository: HttpSearchRepository(transport, uri),
        transfers: TransferEngine(transport, store),
        transport: transport,
        baseUri: uri,
      );
      _session = session;
      _editingEndpoint = false;
    } catch (error) {
      if (error is! _InvalidEndpoint) await _release();
      _error = error;
    }
    _connecting = false;
    if (mounted && _closing == null) setState(() {});
  }

  void _connect() {
    if (_connecting || _closing != null) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    _opening = _open();
  }

  Future<void> _release() async {
    try {
      await _session?.close();
    } finally {
      try {
        await _store?.close();
      } finally {
        await _transport?.close();
        _session = null;
        _store = null;
        _transport = null;
      }
    }
  }

  Future<void> _close() => _closing ??= (() async {
    await _opening;
    await _release();
  })();

  @override
  void dispose() {
    _unregister();
    _endpoint.dispose();
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final session = _session;
    if (session != null && !_editingEndpoint) {
      return ProviderScope(
        overrides: [networkSessionProvider.overrideWithValue(session)],
        child: NetworkPage(
          onChangeEndpoint: () {
            session.setActive(false);
            setState(() => _editingEndpoint = true);
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.networkTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(strings.networkEndpointHelp),
                TextField(
                  key: const ValueKey('network-endpoint'),
                  controller: _endpoint,
                  enabled: !_connecting,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: strings.networkEndpointLabel,
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error is _InvalidEndpoint
                          ? strings.networkEndpointRequired
                          : strings.networkStartupFailed('$_error'),
                    ),
                  ),
                if (_connecting) const LinearProgressIndicator(),
                FilledButton(
                  key: const ValueKey('network-connect'),
                  onPressed: _connecting ? null : _connect,
                  child: Text(
                    _error == null
                        ? strings.networkConnect
                        : strings.networkRetry,
                  ),
                ),
                if (session != null)
                  TextButton(
                    onPressed: _connecting
                        ? null
                        : () => setState(() => _editingEndpoint = false),
                    child: Text(strings.networkKeepEndpoint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
