import 'dart:async';

import 'package:device_lab/features/devices/application/incoming_intents.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/data/device_client.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

typedef HostFactory = Future<DeviceHost> Function(
  DeviceCommandTarget target, {
  String address,
  int port,
});

final class DeviceLabSnapshot {
  const DeviceLabSnapshot({
    required this.onboarding,
    required this.documents,
    required this.activeTab,
    required this.draft,
    required this.dirty,
    required this.pendingIntents,
    required this.discovered,
    required this.connection,
    required this.paused,
    required this.completed,
    this.selectedId,
    this.hostUri,
    this.pairingCode,
    this.remoteSummary,
    this.error,
    this.message,
  });
  final OnboardingState onboarding;
  final Map<String, Map<String, String>> documents;
  final String activeTab;
  final String draft;
  final bool dirty;
  final int pendingIntents;
  final List<DiscoveredDevice> discovered;
  final DeviceConnectionState connection;
  final bool paused;
  final int completed;
  final String? selectedId;
  final Uri? hostUri;
  final String? pairingCode;
  final Map<String, Object?>? remoteSummary;
  final Object? error;
  final String? message;
}

/// One app owner. No socket or discovery starts before the corresponding action.
final class DeviceLabSession implements DeviceCommandTarget {
  DeviceLabSession({
    required this.settings,
    required this.discovery,
    required this.startHost,
    required this.advertise,
    required this.importFile,
    this.links,
    this.canHost = false,
    this.pickDirectory,
    this.pickDocument,
    PairedDeviceClient? client,
  }) : client = client ?? PairedDeviceClient(),
       onboarding = OnboardingCoordinator(settings) {
    incoming = IncomingIntentCoordinator(
      dispatch: _dispatch,
      canNavigate: () async => !_dirty,
    );
  }
  final DeviceSettingsStore settings;
  final DeviceDiscovery discovery;
  final HostFactory startHost;
  final Future<DeviceAdvertisement> Function(String name, int port) advertise;
  final Future<ImportedDocument> Function(String path) importFile;
  final IncomingLinkSource? links;
  final bool canHost;
  final Future<String?> Function()? pickDirectory;
  final Future<ImportedDocument?> Function(String? directory)? pickDocument;
  final PairedDeviceClient client;
  final OnboardingCoordinator onboarding;
  late final IncomingIntentCoordinator incoming;
  final _changes = StreamController<DeviceLabSnapshot>.broadcast();
  Stream<DeviceLabSnapshot> get changes => _changes.stream;
  final _documents = <String, Map<String, String>>{};
  List<DiscoveredDevice> _discovered = [];
  final _subscriptions = <StreamSubscription<Object?>>[];
  DeviceHost? _host;
  DeviceAdvertisement? _advertisement;
  Timer? _task;
  bool _paused = false;
  int _completed = 0;
  int _characters = 0;
  bool _dirty = false;
  bool _closed = false;
  String _tab = 'documents';
  String? _selectedId;
  String _draft = '';
  Map<String, Object?>? _remoteSummary;
  Object? _error;
  String? _message;
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  DeviceLabSnapshot get state => DeviceLabSnapshot(
    onboarding: onboarding.state,
    documents: Map.unmodifiable(
      _documents.map(
        (id, value) => MapEntry(id, Map<String, String>.unmodifiable(value)),
      ),
    ),
    activeTab: _tab,
    draft: _draft,
    dirty: _dirty,
    pendingIntents: incoming.pendingCount,
    discovered: List.unmodifiable(_discovered),
    connection: client.state,
    paused: _paused,
    completed: _completed,
    selectedId: _selectedId,
    hostUri: _host?.uri,
    pairingCode: _host?.pairingCode,
    remoteSummary: _remoteSummary,
    error: _error,
    message: _message,
  );
  void _emit() {
    if (!_closed) _changes.add(state);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Device session is closed');
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    _ensureOpen();
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> initialize() async {
    _ensureOpen();
    final source = links;
    if (source != null) {
      _subscriptions.add(
        source.links.listen(
          (uri) => unawaited(receiveUri(uri)),
          onError: (Object error) {
            _error = error;
            _emit();
          },
        ),
      );
      try {
        final initial = await source.initial();
        if (initial != null) await receiveUri(initial);
      } catch (error) {
        _error = error;
      }
    }
    await onboarding.restore();
    final saved = await settings.read();
    if (saved['documents'] case final Map<String, Object?> raw) {
      for (final entry in raw.entries) {
        _documents[entry.key] = Map<String, String>.from(entry.value as Map);
      }
    }
    if (_documents.isEmpty) {
      _documents['welcome'] = {
        'title': 'Welcome',
        'text':
            'Local documents stay on this device. Only summaries are shared.',
      };
    }
    _selectedId = _documents.keys.first;
    _draft = _documents[_selectedId]!['text']!;
    _subscriptions.add(client.changes.listen((_) => _emit()));
    _subscriptions.add(
      discovery.changes.listen(
        (devices) {
          _discovered = devices;
          _emit();
        },
        onError: (Object error) {
          _error = error;
          _emit();
        },
      ),
    );
    _task = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _closed) return;
      _characters = _documents.values.fold(
        0,
        (total, doc) => total + doc['text']!.runes.length,
      );
      _completed++;
      _emit();
    });
    if (onboarding.state.step == OnboardingStep.complete) {
      await incoming.markReady();
    }
    _emit();
  }

  Future<bool> act(Future<void> Function() action) async {
    _ensureOpen();
    _error = null;
    try {
      await action();
      _emit();
      return true;
    } catch (error) {
      _error = error;
      _emit();
      return false;
    }
  }

  Future<void> saveOnboarding(OnboardingState next) async {
    await _serialize(() => onboarding.save(next));
    if (next.step == OnboardingStep.complete) await incoming.markReady();
    _emit();
  }

  Future<void> skipOnboarding() async {
    await _serialize(onboarding.skip);
    await incoming.markReady();
    _emit();
  }

  Future<void> configureAgain() => saveOnboarding(
    OnboardingState(
      language: onboarding.state.language,
      directory: onboarding.state.directory,
      device: onboarding.state.device,
    ),
  );
  void edit(String text) {
    _ensureOpen();
    _draft = text;
    _dirty = text != _documents[_selectedId]?['text'];
    _emit();
  }

  Future<void> saveDraft() async {
    final id = _selectedId;
    if (id == null) return;
    final text = _draft;
    await _serialize(() async {
      final next = {
        ..._documents,
        id: {..._documents[id]!, 'text': text},
      };
      await settings.write({...await settings.read(), 'documents': next});
      _documents[id] = next[id]!;
      _dirty = _draft != text;
    });
    await incoming.drain();
    _emit();
  }

  Future<void> discardDraft() async {
    _draft = _documents[_selectedId]?['text'] ?? '';
    _dirty = false;
    await incoming.drain();
    _emit();
  }

  void dismissIncoming() {
    incoming.clearPending();
    _emit();
  }

  Future<IncomingResult?> receiveUri(Uri uri) async {
    try {
      final result = await incoming.receive(IncomingIntent.fromUri(uri));
      _message = 'Incoming: ${result.name}';
      _emit();
      return result;
    } catch (error) {
      _error = error;
      _emit();
      return null;
    }
  }

  Future<void> chooseDirectory() async {
    final path = await pickDirectory?.call();
    if (path == null) return;
    final current = onboarding.state;
    await saveOnboarding(
      OnboardingState(
        step: current.step,
        language: current.language,
        directory: path,
        device: current.device,
      ),
    );
  }

  Future<void> importPickedDocument() async {
    final imported = await pickDocument?.call(onboarding.state.directory);
    if (imported == null) return;
    if (_dirty) {
      throw StateError('Save or discard the current draft before importing');
    }
    await _importDocument(imported);
  }

  Future<void> selectDocument(String id) async {
    await incoming.receive(
      IncomingIntent(
        id: 'ui_${DateTime.now().microsecondsSinceEpoch}',
        action: IncomingAction.openDocument,
        value: id,
      ),
    );
    _emit();
  }

  Future<void> _importDocument(ImportedDocument imported) async {
    _ensureOpen();
    final id = 'import_${DateTime.now().microsecondsSinceEpoch}';
    await _serialize(() async {
      final next = {
        ..._documents,
        id: {'title': imported.name, 'text': imported.text},
      };
      await settings.write({...await settings.read(), 'documents': next});
      _documents[id] = next[id]!;
    });
    _selectedId = id;
    _draft = imported.text;
    _tab = 'documents';
    _emit();
  }

  Future<void> _dispatch(IncomingIntent intent) async {
    switch (intent.action) {
      case IncomingAction.showTasks:
        _tab = 'tasks';
      case IncomingAction.openDocument:
        if (!_documents.containsKey(intent.value)) {
          throw StateError('Document does not exist: ${intent.value}');
        }
        _selectedId = intent.value;
        _draft = _documents[_selectedId]!['text']!;
        _tab = 'documents';
      case IncomingAction.importFile:
        await _importDocument(await importFile(intent.value!));
    }
    _emit();
  }

  Future<void> host({bool localNetwork = false}) => _serialize(() async {
    if (_host != null) return;
    final host = await startHost(
      this,
      address: localNetwork ? '0.0.0.0' : '127.0.0.1',
      port: 0,
    );
    try {
      if (localNetwork) {
        _advertisement = await advertise('Koi device', host.uri.port);
      }
      _host = host;
      _emit();
    } catch (_) {
      await host.close();
      rethrow;
    }
  });
  Future<void> stopHosting() => _serialize(() async {
    await _advertisement?.close();
    _advertisement = null;
    await _host?.close();
    _host = null;
    _emit();
  });
  Future<void> discover() => discovery.start();
  Future<void> connect(Uri uri, String code) async {
    await client.connect(uri, code);
    _remoteSummary = await client.execute(DeviceCommand.summary);
    final current = onboarding.state;
    await _serialize(
      () => onboarding.save(
        OnboardingState(
          step: current.step,
          language: current.language,
          directory: current.directory,
          device: uri.toString(),
          skipped: current.skipped,
        ),
      ),
    );
    _emit();
  }

  Future<void> send(DeviceCommand command) async {
    _remoteSummary = await client.execute(command);
    _emit();
  }

  @override
  Future<Map<String, Object?>> execute(DeviceCommand command) async {
    _ensureOpen();
    switch (command) {
      case DeviceCommand.pauseTask:
        _paused = true;
      case DeviceCommand.resumeTask:
        _paused = false;
      case DeviceCommand.summary:
        break;
    }
    _emit();
    return {
      'name': 'Koi device',
      'documents': [
        for (final entry in _documents.entries)
          {
            'id': entry.key,
            'title': entry.value['title'],
            'characters': entry.value['text']!.runes.length,
          },
      ],
      'task': {
        'name': 'Summary refresh',
        'paused': _paused,
        'completed': _completed,
        'characters': _characters,
      },
    };
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _task?.cancel();
    final errors = <Object>[];
    for (final cleanup in <Future<void> Function()>[
      for (final subscription in _subscriptions) subscription.cancel,
      incoming.close,
      () => _pending,
      client.close,
      discovery.close,
      if (_advertisement != null) _advertisement!.close,
      if (_host != null) _host!.close,
      onboarding.close,
      settings.close,
    ]) {
      try {
        await cleanup();
      } catch (error) {
        errors.add(error);
      }
    }
    // A hidden Riverpod subtree may pause UI events. Resource cleanup must not
    // wait for that observer to resume; accepted IO above has already drained.
    unawaited(_changes.close());
    if (errors.isNotEmpty) throw StateError('Device cleanup failed: $errors');
  }
}
