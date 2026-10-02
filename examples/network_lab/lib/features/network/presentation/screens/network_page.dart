import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/presentation/providers/network_providers.dart';

class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({this.onChangeEndpoint, super.key});
  final VoidCallback? onChangeEndpoint;
  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage>
    with WidgetsBindingObserver {
  late final TextEditingController _query;
  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
      text: ref.read(networkSessionProvider).snapshot.query,
    );
    WidgetsBinding.instance.addObserver(this);
    ref.read(networkSessionProvider).setActive(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => ref
      .read(networkSessionProvider)
      .setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _query.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final value = ref.watch(networkSnapshotProvider);
    final session = ref.read(networkSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.networkLabTitle),
        actions: [
          if (widget.onChangeEndpoint != null)
            IconButton(
              onPressed: widget.onChangeEndpoint,
              tooltip: strings.networkChangeEndpoint,
              icon: const Icon(Icons.settings_ethernet),
            ),
        ],
      ),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(strings.networkErrorDetails('$error'))),
        data: (state) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: InputDecoration(
                  labelText: strings.networkSearchLabel,
                ),
                onChanged: session.search,
              ),
              Text(
                strings.networkReachability(
                  strings.networkReachabilityState(state.reachability.name),
                ),
              ),
              if (state.searching || state.appending)
                const LinearProgressIndicator(),
              if (state.error != null)
                Text(
                  strings.networkErrorDetails(state.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: state.items.isEmpty
                    ? Center(
                        child: Text(
                          state.query.isEmpty
                              ? strings.networkEnterQuery
                              : state.searching
                              ? strings.networkSearching
                              : state.error == null
                              ? strings.networkNoResults
                              : strings.networkRequestFailed,
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.items.length,
                        itemBuilder: (context, index) => ListTile(
                          key: ValueKey(state.items[index].id),
                          title: Text(state.items[index].label),
                        ),
                      ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: state.query.isEmpty || state.searching
                        ? null
                        : session.refresh,
                    child: Text(strings.networkRefresh),
                  ),
                  TextButton(
                    onPressed:
                        state.nextCursor == null ||
                            state.searching ||
                            state.appending
                        ? null
                        : session.loadMore,
                    child: Text(strings.networkLoadMore),
                  ),
                  TextButton(
                    onPressed: session.clearCache,
                    child: Text(strings.networkClearQueryCache),
                  ),
                ],
              ),
              const Divider(),
              Text(
                strings.networkTransferProgress(
                  strings.networkTransferPhase(state.transfer.phase.name),
                  state.transfer.received,
                  state.transfer.total?.toString() ?? '?',
                ),
              ),
              if (state.transfer.error != null)
                Text(strings.networkTransferError(state.transfer.error!)),
              if (state.transfer.digest != null)
                SelectableText('SHA256: ${state.transfer.digest}'),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        state.transfer.phase == TransferPhase.downloading ||
                            state.transfer.phase == TransferPhase.cancelling
                        ? null
                        : session.download,
                    child: Text(strings.networkDownloadRetry),
                  ),
                  TextButton(
                    onPressed: state.transfer.phase == TransferPhase.downloading
                        ? session.cancelDownload
                        : null,
                    child: Text(strings.networkCancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
