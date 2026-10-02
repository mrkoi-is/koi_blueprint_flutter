import 'dart:async';

import 'package:network_lab/features/network/domain/network_ports.dart';

class FakeTransport implements HttpTransport {
  FakeTransport(this.handler);
  final FutureOr<HttpPayload> Function(
    Uri,
    String,
    Map<String, String>,
    Cancellation,
  )
  handler;
  int requests = 0;
  bool closed = false;
  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    requests++;
    cancellation.check();
    return handler(uri, method, headers, cancellation);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class MemoryTransferStore implements TransferStore {
  final stages = <String, List<int>>{};
  final completed = <String, List<int>>{};
  final metas = <String, TransferMetadata>{};
  final digests = <String, String>{};
  bool closed = false;
  @override
  Future<TransferMetadata?> metadata(String id) async => metas[id];
  @override
  Future<void> begin(String id, TransferMetadata metadata) async {
    stages[id] = [];
    metas[id] = metadata;
  }

  @override
  Future<int> length(String id) async => stages[id]?.length ?? 0;
  @override
  Future<void> append(String id, List<int> bytes) async =>
      stages[id]!.addAll(bytes);
  @override
  Stream<List<int>> read(String id) =>
      Stream.value(stages[id] ?? completed[id]!);
  @override
  Future<void> commit(String id, String digest) async {
    completed[id] = stages.remove(id)!;
    metas.remove(id);
    digests[id] = digest;
  }

  @override
  Future<void> discard(String id) async {
    stages.remove(id);
    metas.remove(id);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
