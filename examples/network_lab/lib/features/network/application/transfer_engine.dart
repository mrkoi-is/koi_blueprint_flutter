import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

/// A bounded prefetch window overlaps range requests but commits only contiguous,
/// fully validated ranges. Staging writes remain ordered on every platform.
final class TransferEngine {
  TransferEngine(
    this.transport,
    this.store, {
    this.rangeBytes = 256 * 1024,
    this.maxBytes = 512 * 1024 * 1024,
    this.maxConcurrentRanges = 3,
  }) {
    if (rangeBytes < 1 ||
        rangeBytes > 8 * 1024 * 1024 ||
        maxBytes < 1 ||
        maxConcurrentRanges < 1 ||
        maxConcurrentRanges > 8) {
      throw ArgumentError('Range size must be 1..8 MiB and concurrency 1..8');
    }
  }
  final HttpTransport transport;
  final TransferStore store;
  final int rangeBytes, maxBytes, maxConcurrentRanges;
  Future<String> download(
    Uri uri, {
    required String id,
    required Cancellation cancellation,
    required void Function(TransferSnapshot) progress,
    String? expectedSha256,
  }) async {
    cancellation.check();
    final head = await transport.open(
      uri,
      method: 'HEAD',
      cancellation: cancellation,
    );
    await head.body.drain<void>();
    if (head.status != 200) throw StateError('Metadata HTTP ${head.status}');
    final total = int.tryParse(head.headers['content-length'] ?? '');
    if (total != null && (total < 0 || total > maxBytes)) {
      throw StateError('Transfer exceeds quota');
    }
    final rawTag = head.headers['etag'];
    final etag = rawTag != null && !rawTag.startsWith('W/') ? rawTag : null;
    final metadata = TransferMetadata(
      source: uri.toString(),
      etag: etag,
      total: total,
    );
    final previous = await store.metadata(id);
    var offset = await store.length(id);
    final ranges =
        head.headers['accept-ranges'] == 'bytes' &&
        total != null &&
        etag != null;
    if (!ranges ||
        previous == null ||
        !metadata.matches(previous) ||
        offset > total) {
      await store.begin(id, metadata);
      offset = 0;
    }
    progress(
      TransferSnapshot(
        phase: TransferPhase.downloading,
        received: offset,
        total: total,
      ),
    );
    try {
      if (ranges) {
        offset = await _downloadRanges(
          uri,
          id: id,
          start: offset,
          total: total,
          etag: etag,
          cancellation: cancellation,
          progress: progress,
        );
      } else {
        cancellation.check();
        final response = await transport.open(uri, cancellation: cancellation);
        if (response.status != 200) {
          cancellation.cancel();
          throw StateError('Download HTTP ${response.status}');
        }
        await for (final bytes in response.body) {
          cancellation.check();
          if (offset + bytes.length > maxBytes ||
              (total != null && offset + bytes.length > total)) {
            cancellation.cancel();
            await store.discard(id);
            throw StateError('Response length exceeds metadata');
          }
          await store.append(id, bytes);
          offset += bytes.length;
          progress(
            TransferSnapshot(
              phase: TransferPhase.downloading,
              received: offset,
              total: total,
            ),
          );
        }
        cancellation.check();
      }
      if (total != null && offset != total) {
        throw StateError('Incomplete response');
      }
      cancellation.check();
      final digest = (await sha256.bind(store.read(id)).first).toString();
      cancellation.check();
      if (expectedSha256 != null && digest != expectedSha256) {
        await store.discard(id);
        throw StateError('SHA256 mismatch');
      }
      await store.commit(id, digest);
      progress(
        TransferSnapshot(
          phase: TransferPhase.complete,
          received: offset,
          total: total,
          digest: digest,
        ),
      );
      return digest;
    } on RequestCancelled {
      await store.discard(id);
      rethrow;
    }
    // Network interruption retains validated staged ranges for a fresh attempt.
    // A user cancellation always discards them through the owner's cancel path.
  }

  Future<int> _downloadRanges(
    Uri uri, {
    required String id,
    required int start,
    required int total,
    required String etag,
    required Cancellation cancellation,
    required void Function(TransferSnapshot) progress,
  }) async {
    final group = Cancellation();
    final detach = cancellation.onCancel(group.cancel);
    final pending = <Future<Uint8List?>>[];
    Object? failure;
    StackTrace? failureStack;
    var next = start;
    var committed = start;
    var received = start;

    void fill() {
      while (!group.isCancelled &&
          next < total &&
          pending.length < maxConcurrentRanges) {
        final begin = next;
        final end = math.min(begin + rangeBytes - 1, total - 1);
        next = end + 1;
        pending.add(() async {
          try {
            return await _readRange(uri, begin, end, total, etag, group, (
              count,
            ) {
              received += count;
              progress(
                TransferSnapshot(
                  phase: TransferPhase.downloading,
                  received: received,
                  total: total,
                ),
              );
            });
          } catch (error, stack) {
            failure ??= error;
            failureStack ??= stack;
            group.cancel();
            return null;
          }
        }());
      }
    }

    try {
      fill();
      while (pending.isNotEmpty) {
        final bytes = await pending.first;
        cancellation.check();
        if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
        await store.append(id, bytes!);
        committed += bytes.length;
        // Keep this slot occupied until its write settles, so slow storage
        // cannot create an unbounded queue of completed response buffers.
        pending.removeAt(0);
        fill();
      }
      cancellation.check();
      return committed;
    } on _InvalidRange {
      await store.discard(id);
      rethrow;
    } finally {
      detach();
      group.cancel();
      // Every started reader settles before the owner can close the store or
      // transport; all reader errors were captured at the point of creation.
      await Future.wait(pending);
    }
  }

  Future<Uint8List> _readRange(
    Uri uri,
    int start,
    int end,
    int total,
    String etag,
    Cancellation cancellation,
    void Function(int) onBytes,
  ) async {
    final response = await transport.open(
      uri,
      cancellation: cancellation,
      headers: {'Range': 'bytes=$start-$end', 'If-Range': etag},
    );
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
        .firstMatch(response.headers['content-range'] ?? '');
    if (response.status != 206 ||
        match == null ||
        int.parse(match[1]!) != start ||
        int.parse(match[2]!) != end ||
        int.parse(match[3]!) != total ||
        response.headers['etag'] != etag) {
      throw _InvalidRange('Range response changed or is invalid');
    }
    final expected = end - start + 1;
    final buffer = BytesBuilder(copy: false);
    await for (final bytes in response.body) {
      cancellation.check();
      if (buffer.length + bytes.length > expected) {
        throw _InvalidRange('Response length exceeds metadata');
      }
      buffer.add(bytes);
      onBytes(bytes.length);
      cancellation.check();
    }
    cancellation.check();
    if (buffer.length != expected) throw StateError('Incomplete range');
    return buffer.takeBytes();
  }
}

final class _InvalidRange extends StateError {
  _InvalidRange(super.message);
}
