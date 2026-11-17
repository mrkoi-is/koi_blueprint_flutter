import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_diagnostics/src/diagnostic_strings.dart';
import 'package:koi_diagnostics/src/viewer_html.dart';

/// Owns the listener and Android keepalive; borrows the host store.
final class DiagnosticLan extends ChangeNotifier with WidgetsBindingObserver {
  DiagnosticLan(this.store, {this.androidKeepAlive = true, bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid {
    WidgetsBinding.instance.addObserver(this);
  }
  final BoundedDiagnosticStore Function() store;
  final bool androidKeepAlive;
  final bool _isAndroid;
  HttpServer? _server;
  final _streams = <HttpResponse, StreamSubscription<int>>{};
  final _responses = <HttpResponse>{};
  final _timers = <HttpResponse, Timer>{};
  bool _busy = false;
  bool _closed = false;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  bool _ownsService = false;
  int _generation = 0;
  String? _credential;
  Object? _error;
  String? _address;
  bool? notificationGranted;
  bool? batteryOptimizationIgnored;
  bool get supported => true;
  bool get running => _server != null;
  bool get busy => _busy;
  String? get address => _address;
  String? get credential => _credential;
  Object? get error => _error;
  Future<List<String>> interfaces() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback) a.address,
  ];

  Future<void> start({String? address, String language = 'en'}) async {
    if (_closed || running || _busy) return;
    final generation = ++_generation;
    _busy = true;
    _error = null;
    _notify();
    try {
      final host = address ?? (await interfaces()).firstOrNull;
      if (host == null) throw StateError('No LAN interface available');
      if (_isAndroid && androidKeepAlive) {
        final strings = DiagnosticStrings(language);
        // The plugin creates channels only once. Keep the same channel and its
        // user settings while updating the name when the language changes.
        await const MethodChannel('koi/diagnostics').invokeMethod<void>(
          'localizeNotificationChannel',
          {'name': strings.notificationTitle},
        );
        if (generation != _generation) return;
        // Keep this option null: 11.0.3's stopWithTask option also stops on pause.
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'koi_diagnostics',
            channelName: strings.notificationTitle,
          ),
          iosNotificationOptions: const IOSNotificationOptions(),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowWifiLock: true,
            autoRunOnBoot: false,
            autoRunOnMyPackageReplaced: false,
            allowAutoRestart: false,
          ),
        );
        notificationGranted =
            await FlutterForegroundTask.requestNotificationPermission() ==
            NotificationPermission.granted;
        if (generation != _generation) return;
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
        batteryOptimizationIgnored =
            await FlutterForegroundTask.isIgnoringBatteryOptimizations;
        if (generation != _generation) return;
        if (await FlutterForegroundTask.isRunningService) {
          throw StateError('Another foreground task already owns the service');
        }
        final result = await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.connectedDevice],
          notificationTitle: strings.notificationTitle,
          notificationText: strings.notificationText,
        );
        if (result is ServiceRequestFailure) {
          throw StateError('${result.error}');
        }
        _ownsService = true;
      }
      if (generation != _generation) return;
      final server = await HttpServer.bind(host, 0);
      _server = server;
      if (generation != _generation) {
        await _shutdown();
        return;
      }
      _credential = base64Url
          .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
      _address = 'http://$host:${server.port}';
      server.listen(
        (request) => unawaited(_serve(request, language)),
        onError: (Object error) {
          _error = error;
          unawaited(stop());
        },
      );
    } catch (error) {
      _error = error;
      await _shutdown();
    } finally {
      if (generation != _generation) await _shutdown();
      _busy = false;
      _notify();
    }
  }

  Future<void> _serve(HttpRequest request, String language) async {
    final response = request.response;
    _responses.add(response);
    unawaited(
      response.done.then<void>(
        (_) => _responses.remove(response),
        onError: (Object _) {
          _responses.remove(response);
        },
      ),
    );
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    try {
      if (request.method != 'GET') {
        response.statusCode = 405;
        await response.close();
        return;
      }
      if (request.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.headers.set(
          'Content-Security-Policy',
          "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
        );
        response.write(viewerHtml(language));
        await response.close();
        return;
      }
      final cookie = request.cookies
          .where((c) => c.name == 'koi_diagnostic')
          .firstOrNull
          ?.value;
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (_credential == null ||
          (cookie != _credential && auth != 'Bearer $_credential')) {
        response.statusCode = 401;
        await response.close();
        return;
      }
      final query = DiagnosticQuery(
        text: request.uri.queryParameters['text'] ?? '',
        kind: request.uri.queryParameters['kind'],
        source: request.uri.queryParameters['source'],
        level: AppLogLevel.values
            .where((v) => v.name == request.uri.queryParameters['level'])
            .firstOrNull,
      );
      switch (request.uri.path) {
        case '/events':
          response.bufferOutput = false;
          response.headers.contentType = ContentType('text', 'event-stream');
          response.write('data: ${store().revision}\n\n');
          await response.flush();
          var dirty = false;
          var sending = false;
          Future<void> publish() async {
            if (!dirty || sending) return;
            dirty = false;
            sending = true;
            try {
              response.write('data: ${store().revision}\n\n');
              await response.flush();
            } catch (_) {
              _timers.remove(response)?.cancel();
              await _streams.remove(response)?.cancel();
              try {
                await response.close();
              } catch (_) {
                /* Disconnected. */
              }
            } finally {
              sending = false;
            }
          }
          final subscription = store().watchChanges().listen(
            (_) => dirty = true,
          );
          _streams[response] = subscription;
          _timers[response] = Timer.periodic(
            const Duration(milliseconds: 250),
            (_) => unawaited(publish()),
          );
          await response.done;
          _timers.remove(response)?.cancel();
          await _streams.remove(response)?.cancel();
        case '/export':
          response.headers.contentType = ContentType('application', 'x-ndjson');
          response.headers.set(
            'Content-Disposition',
            'attachment; filename="diagnostics.ndjson"',
          );
          await response.addStream(store().exportSnapshot(query));
          await response.close();
        case '/records':
          final cursor = int.tryParse(
            request.uri.queryParameters['cursor'] ?? '',
          );
          final page = store().query(query, cursor: cursor);
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'items': page.items.map((e) => e.toJson()).toList(),
              'nextCursor': page.nextCursor,
              'revision': page.revision,
            }),
          );
          await response.close();
        default:
          response.statusCode = 404;
          await response.close();
      }
    } catch (_) {
      _timers.remove(response)?.cancel();
      await _streams.remove(response)?.cancel();
      try {
        await response.close();
      } catch (_) {
        /* Peer disconnected. */
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      unawaited(stop());
    }
  }

  Future<void> _shutdown() async {
    _credential = null;
    _address = null;
    final server = _server;
    _server = null;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final sub in _streams.values) {
      await sub.cancel();
    }
    _streams.clear();
    await server?.close(force: true);
    _responses.clear();
    if (_ownsService) {
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) _error = result.error;
      _ownsService = false;
    }
  }

  Future<void> stop() async {
    ++_generation;
    await _shutdown();
    _notify();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await stop();
    WidgetsBinding.instance.removeObserver(this);
    dispose();
  }
}
