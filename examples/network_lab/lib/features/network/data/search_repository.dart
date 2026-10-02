import 'dart:convert';

import 'package:network_lab/features/network/data/response_cache.dart';
import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

final class HttpSearchRepository implements SearchRepository {
  HttpSearchRepository(
    this.transport,
    this.baseUri, {
    ResponseCache? cache,
    this.scope = 'anonymous',
    this.adapterVersion = '1',
  }) : cache = cache ?? ResponseCache();
  final HttpTransport transport;
  final Uri baseUri;
  final ResponseCache cache;
  final String scope, adapterVersion;
  @override
  Future<NetworkPage> search(
    String query, {
    String? cursor,
    required Cancellation cancellation,
    bool refresh = false,
  }) async {
    cancellation.check();
    query = query.trim();
    if (query.isEmpty) return const NetworkPage(items: []);
    final uri = baseUri
        .resolve('catalog')
        .replace(queryParameters: {'q': query, 'cursor': ?cursor});
    final key = jsonEncode([scope, adapterVersion, uri.toString()]);
    final cached = refresh ? null : cache.get(key);
    if (cached != null) {
      try {
        return _decode(cached);
      } catch (_) {
        cache.remove(key);
      }
    }
    final response = await transport.open(uri, cancellation: cancellation);
    final bytes = <int>[];
    await for (final chunk in response.body) {
      cancellation.check();
      if (bytes.length + chunk.length > 1024 * 1024) {
        cancellation.cancel();
        throw const FormatException('Catalog response exceeds 1 MiB');
      }
      bytes.addAll(chunk);
    }
    cancellation.check();
    if (response.status != 200) {
      throw StateError('Catalog HTTP ${response.status}');
    }
    final page = _decode(bytes);
    if (cursor != null && page.nextCursor == cursor) {
      throw const FormatException('Cursor did not advance');
    }
    cache.put(key, bytes);
    return page;
  }

  NetworkPage _decode(List<int> bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return NetworkPage(
      items: (json['items'] as List<dynamic>).map((value) {
        final item = value as Map<String, dynamic>;
        return NetworkEntry(
          id: item['id'] as String,
          label: item['label'] as String,
        );
      }).toList(),
      nextCursor: json['nextCursor'] as String?,
      total: json['total'] as int?,
    );
  }

  @override
  void clear() => cache.clear();
}
