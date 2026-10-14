import 'package:freezed_annotation/freezed_annotation.dart';

part 'network_models.freezed.dart';

@freezed
abstract class NetworkEntry with _$NetworkEntry {
  const factory NetworkEntry({required String id, required String label}) =
      _NetworkEntry;
}

@freezed
abstract class NetworkPage with _$NetworkPage {
  const factory NetworkPage({
    required List<NetworkEntry> items,
    String? nextCursor,
    int? total,
  }) = _NetworkPage;
}

enum TransferPhase {
  idle,
  downloading,
  cancelling,
  cancelled,
  complete,
  failed,
}

enum Reachability { unknown, reachable, unreachable }

@freezed
abstract class TransferSnapshot with _$TransferSnapshot {
  const factory TransferSnapshot({
    @Default(TransferPhase.idle) TransferPhase phase,
    @Default(0) int received,
    int? total,
    String? digest,
    String? error,
  }) = _TransferSnapshot;
}

@freezed
abstract class NetworkSnapshot with _$NetworkSnapshot {
  const factory NetworkSnapshot({
    @Default('') String query,
    @Default(<NetworkEntry>[]) List<NetworkEntry> items,
    String? nextCursor,
    @Default(false) bool searching,
    @Default(false) bool appending,
    String? error,
    @Default(<String>[]) List<String> history,
    @Default(Reachability.unknown) Reachability reachability,
    @Default(TransferSnapshot()) TransferSnapshot transfer,
  }) = _NetworkSnapshot;
}
