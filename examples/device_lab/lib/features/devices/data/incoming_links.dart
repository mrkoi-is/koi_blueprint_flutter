import 'dart:async';

import 'package:koi_core/koi_core.dart';

import 'package:app_links/app_links.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

/// Normal web navigation is not an incoming command. Use ?koi-intent=koi%3A...
/// when the host router owns paths, or a direct /tasks or /document URL.
Uri? normalizeIncomingUri(Uri uri) {
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final nested = uri.queryParameters['koi-intent'];
    if (nested != null) return Uri.tryParse(nested);
    if (uri.fragment.startsWith('/tasks') ||
        uri.fragment.startsWith('/document')) {
      final fragment = Uri.parse(uri.fragment);
      return uri.replace(
        path: fragment.path,
        query: fragment.query,
        fragment: '',
      );
    }
    if (uri.path != '/tasks' && uri.path != '/document') return null;
  }
  return uri;
}

/// Construct before restoring settings so a cold-start event can be queued.
final class AppIncomingLinks implements IncomingLinkSource {
  AppIncomingLinks() : _links = AppLinks();
  final AppLinks _links;
  @override
  Stream<Uri> get links => _links.uriLinkStream
      .map(normalizeIncomingUri)
      .where((value) => value != null)
      .cast<Uri>();
  @override
  Future<Uri?> initial() async {
    final uri = await _links.getInitialLink();
    return uri == null ? null : normalizeIncomingUri(uri);
  }
}

/// Host initializer owns this bounded inbox; pages borrow it. Commands received
/// before a page or its storage is ready are replayed through the same queue.
final class IncomingLinkInbox implements IncomingLinkSource {
  static IncomingLinkInbox? _instance;
  static IncomingLinkInbox get instance => _instance ??= IncomingLinkInbox();
  IncomingLinkInbox({this._source, void Function()? onIncoming})
    : _onIncoming =
          onIncoming ??
          (() => CapabilityNavigation.instance.open('incoming-intents'));
  final void Function() _onIncoming;
  IncomingLinkSource? _source;
  StreamSubscription<Uri>? _subscription;
  final _queued = <Uri>[];
  final _events = StreamController<Uri>.broadcast();
  bool _closed = false;
  void start() {
    if (_closed) throw StateError('Incoming inbox closed');
    if (_subscription != null) return;
    final source = _source ??= AppIncomingLinks();
    _subscription = source.links.listen(_receive, onError: _events.addError);
    unawaited(
      source.initial().then(
        (uri) {
          if (uri != null) _receive(uri);
        },
        onError: (Object error, StackTrace stack) {
          if (!_closed) _events.addError(error, stack);
        },
      ),
    );
  }

  void _receive(Uri uri) {
    if (_closed) return;
    try {
      IncomingIntent.fromUri(uri);
    } catch (error) {
      _events.addError(error);
      return;
    }
    _onIncoming();
    if (_events.hasListener) {
      _events.add(uri);
      return;
    }
    if (_queued.any((value) => value == uri)) return;
    if (_queued.length == 64) _queued.removeAt(0);
    _queued.add(uri);
  }

  @override
  Stream<Uri> get links => Stream<Uri>.multi((controller) {
    final subscription = _events.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    for (final uri in _queued) {
      controller.add(uri);
    }
    _queued.clear();
    controller.onCancel = subscription.cancel;
  });
  @override
  Future<Uri?> initial() async => null;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_instance, this)) _instance = null;
    await _subscription?.cancel();
    _queued.clear();
    unawaited(_events.close());
  }
}
