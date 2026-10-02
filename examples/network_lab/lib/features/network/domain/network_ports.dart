import 'dart:async';

import 'package:network_lab/shared/network/domain/http_ports.dart';
export 'package:network_lab/shared/network/domain/http_ports.dart';
import 'package:network_lab/features/network/domain/network_models.dart';

abstract interface class SearchRepository {
  Future<NetworkPage> search(
    String query, {
    String? cursor,
    required Cancellation cancellation,
    bool refresh = false,
  });
  void clear();
}

final class TransferMetadata {
  const TransferMetadata({
    required this.source,
    required this.etag,
    required this.total,
  });
  final String source;
  final String? etag;
  final int? total;
  Map<String, Object?> toJson() => {
    'source': source,
    'etag': etag,
    'total': total,
  };
  factory TransferMetadata.fromJson(Map<String, dynamic> value) =>
      TransferMetadata(
        source: value['source'] as String,
        etag: value['etag'] as String?,
        total: value['total'] as int?,
      );
  bool matches(TransferMetadata other) =>
      source == other.source &&
      etag != null &&
      etag == other.etag &&
      total == other.total;
}

/// Staging is separate from committed assets. A failed or cancelled attempt is
/// never a completed artifact. Only transfer-owned IDs can be removed.
abstract interface class TransferStore {
  Future<TransferMetadata?> metadata(String id);
  Future<void> begin(String id, TransferMetadata metadata);
  Future<int> length(String id);
  Future<void> append(String id, List<int> bytes);
  Stream<List<int>> read(String id);
  Future<void> commit(String id, String digest);
  Future<void> discard(String id);
  Future<void> close();
}

abstract interface class NetworkSessionPort {
  NetworkSnapshot get snapshot;
  Stream<NetworkSnapshot> get changes;
  void search(String query);
  Future<void> refresh();
  Future<void> loadMore();
  Future<void> download();
  Future<void> cancelDownload();
  void clearCache();
  void setActive(bool active);
  Future<void> close();
}
