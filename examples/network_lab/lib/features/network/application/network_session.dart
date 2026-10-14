import 'dart:async';

import 'package:network_lab/features/network/application/reachability_monitor.dart';
import 'package:network_lab/features/network/application/transfer_engine.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

final class NetworkSession implements NetworkSessionPort {
  NetworkSession({
    required this.repository,
    required this.transfers,
    required HttpTransport transport,
    required this.baseUri,
    this.debounce = const Duration(milliseconds: 300),
    this.historyLimit = 20,
  }) {
    if (historyLimit < 0 || debounce < Duration.zero) {
      throw ArgumentError('History and debounce limits must not be negative');
    }
    _monitor = ReachabilityMonitor(transport, baseUri.resolve('health'), (
      value,
    ) {
      final wasOffline = _snapshot.reachability == Reachability.unreachable;
      _emit(_snapshot.copyWith(reachability: value));
      if (wasOffline &&
          value == Reachability.reachable &&
          _snapshot.query.isNotEmpty) {
        unawaited(refresh());
      }
    });
  }
  final SearchRepository repository;
  final TransferEngine transfers;
  final Uri baseUri;
  final Duration debounce;
  final int historyLimit;
  late final ReachabilityMonitor _monitor;
  final _changes = StreamController<NetworkSnapshot>.broadcast(sync: true);
  final _searches = <Future<void>>{};
  NetworkSnapshot _snapshot = const NetworkSnapshot();
  bool _closed = false;
  Future<void>? _closing;
  Timer? _debounce;
  Cancellation? _queryCancel;
  Cancellation? _transferCancel;
  Future<void>? _append;
  Future<void>? _downloading;
  int _generation = 0;
  @override
  NetworkSnapshot get snapshot => _snapshot;
  @override
  Stream<NetworkSnapshot> get changes => _changes.stream;
  void _emit(NetworkSnapshot state) {
    if (_closed) return;
    _snapshot = state;
    _changes.add(state);
  }

  @override
  void search(String query) {
    if (_closed) return;
    _debounce?.cancel();
    _queryCancel?.cancel();
    ++_generation;
    _append = null;
    query = query.trim();
    _emit(
      _snapshot.copyWith(
        query: query,
        items: [],
        nextCursor: null,
        error: null,
        searching: query.isNotEmpty,
        appending: false,
      ),
    );
    if (query.isNotEmpty) {
      _debounce = Timer(debounce, () => unawaited(_search()));
    }
  }

  Future<void> _search({bool refresh = false, String? cursor}) {
    final pending = _executeSearch(refresh: refresh, cursor: cursor);
    _searches.add(pending);
    unawaited(pending.whenComplete(() => _searches.remove(pending)));
    return pending;
  }

  Future<void> _executeSearch({required bool refresh, String? cursor}) async {
    if (_closed || _snapshot.query.isEmpty) return;
    final generation = ++_generation;
    _queryCancel?.cancel();
    final cancellation = _queryCancel = Cancellation();
    final previous = _snapshot;
    _emit(
      previous.copyWith(
        searching: cursor == null,
        appending: cursor != null,
        error: null,
      ),
    );
    try {
      final page = await repository.search(
        previous.query,
        cursor: cursor,
        cancellation: cancellation,
        refresh: refresh,
      );
      if (_closed || generation != _generation || cancellation.isCancelled) {
        return;
      }
      if (cursor != null && page.nextCursor == cursor) {
        throw StateError('Cursor did not advance');
      }
      final values = <String, NetworkEntry>{
        if (cursor != null)
          for (final item in previous.items) item.id: item,
      };
      for (final item in page.items) {
        values[item.id] = item;
      }
      final history = [
        previous.query,
        ..._snapshot.history.where((value) => value != previous.query),
      ].take(historyLimit).toList();
      _emit(
        _snapshot.copyWith(
          items: values.values.toList(),
          nextCursor: page.nextCursor,
          searching: false,
          appending: false,
          error: null,
          history: history,
        ),
      );
    } catch (error) {
      if (!_closed && generation == _generation && !cancellation.isCancelled) {
        _emit(
          _snapshot.copyWith(
            searching: false,
            appending: false,
            error: error.toString(),
          ),
        );
      }
    }
  }

  @override
  Future<void> refresh() {
    _debounce?.cancel();
    _append = null;
    return _search(refresh: true);
  }

  @override
  Future<void> loadMore() {
    if (_closed || _snapshot.searching || _snapshot.nextCursor == null) {
      return Future.value();
    }
    final current = _append;
    if (current != null) return current;
    final pending = _search(cursor: _snapshot.nextCursor);
    _append = pending;
    unawaited(
      pending.whenComplete(() {
        if (identical(_append, pending)) _append = null;
      }),
    );
    return pending;
  }

  @override
  Future<void> download() {
    if (_closed) return Future.value();
    final current = _downloading;
    if (current != null) return current;
    final cancellation = _transferCancel = Cancellation();
    final pending = _download(cancellation);
    _downloading = pending;
    unawaited(
      pending.whenComplete(() {
        if (identical(_downloading, pending)) {
          _downloading = null;
          _transferCancel = null;
        }
      }),
    );
    return pending;
  }

  Future<void> _download(Cancellation cancellation) async {
    _emit(
      _snapshot.copyWith(
        transfer: const TransferSnapshot(phase: TransferPhase.downloading),
      ),
    );
    try {
      await transfers.download(
        baseUri.resolve('file'),
        id: 'fixture_download',
        cancellation: cancellation,
        progress: (value) {
          // Once the atomic commit succeeds, completion wins a simultaneous cancel.
          if (!cancellation.isCancelled ||
              value.phase == TransferPhase.complete) {
            _emit(_snapshot.copyWith(transfer: value));
          }
        },
      );
    } catch (error) {
      if (error is RequestCancelled) {
        await transfers.store.discard('fixture_download');
        _emit(
          _snapshot.copyWith(
            transfer: _snapshot.transfer.copyWith(
              phase: TransferPhase.cancelled,
              error: null,
            ),
          ),
        );
      } else {
        _emit(
          _snapshot.copyWith(
            transfer: _snapshot.transfer.copyWith(
              phase: TransferPhase.failed,
              error: error.toString(),
            ),
          ),
        );
      }
    }
  }

  @override
  Future<void> cancelDownload() async {
    final current = _downloading;
    if (current == null ||
        _snapshot.transfer.phase != TransferPhase.downloading) {
      return;
    }
    _emit(
      _snapshot.copyWith(
        transfer: _snapshot.transfer.copyWith(phase: TransferPhase.cancelling),
      ),
    );
    _transferCancel?.cancel();
    await current;
  }

  @override
  void clearCache() => repository.clear();
  @override
  void setActive(bool active) => _monitor.setActive(active);
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    ++_generation;
    _debounce?.cancel();
    _queryCancel?.cancel();
    _transferCancel?.cancel();
    _monitor.close();
    await Future.wait(List.of(_searches));
    await _downloading;
    repository.clear();
    await _changes.close();
  }
}
