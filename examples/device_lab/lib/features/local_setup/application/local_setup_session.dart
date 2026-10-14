import 'dart:async';

import 'package:device_lab/features/devices/application/incoming_intents.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

/// Local-only owner: no discovery, host, socket client or network dependency.
final class LocalSetupSession {
  LocalSetupSession({
    required this.store,
    this.links,
    required this.pickDirectory,
    required this.pickDocument,
    required this.importFile,
    this.requireOnboarding = true,
  }) : onboarding = OnboardingCoordinator(store) {
    incoming = IncomingIntentCoordinator(
      dispatch: _dispatch,
      canNavigate: () async => !dirty,
    );
  }
  final DeviceSettingsStore store;
  final bool requireOnboarding;
  final IncomingLinkSource? links;
  final Future<String?> Function() pickDirectory;
  final Future<ImportedDocument?> Function(String?) pickDocument;
  final Future<ImportedDocument> Function(String) importFile;
  final OnboardingCoordinator onboarding;
  late final IncomingIntentCoordinator incoming;
  final _changes = StreamController<int>.broadcast();
  int _revision = 0;
  Stream<int> get changes => _changes.stream;
  StreamSubscription<Uri>? _links;
  final documents = <String, Map<String, String>>{};
  String selectedId = 'welcome';
  String draft = '';
  String tab = 'documents';
  bool dirty = false;
  Object? error;
  bool _closed = false;
  Future<void> _pending = Future.value();
  Future<void>? _closing;
  void _emit() {
    // StreamProvider compares successive values; every committed state change
    // must publish a distinct revision, including external incoming events.
    if (!_closed) _changes.add(++_revision);
  }

  Future<void> initialize() async {
    _links = links?.links.listen(
      (uri) => unawaited(receive(uri)),
      onError: (Object value) {
        error = value;
        _emit();
      },
    );
    final initial = await links?.initial();
    if (initial != null) await receive(initial);
    await onboarding.restore();
    final values = await store.read();
    if (values['documents'] case final Map<String, Object?> raw) {
      for (final entry in raw.entries) {
        documents[entry.key] = Map<String, String>.from(entry.value as Map);
      }
    }
    if (documents.isEmpty) {
      documents['welcome'] = {'title': 'Welcome', 'text': 'Local document'};
    }
    selectedId = documents.keys.first;
    draft = documents[selectedId]!['text']!;
    if (!requireOnboarding ||
        onboarding.state.step == OnboardingStep.complete) {
      await incoming.markReady();
    }
    _emit();
  }

  Future<void> _serial(Future<void> Function() action) {
    if (_closed) throw StateError('Local setup closed');
    final future = _pending.then((_) => action());
    _pending = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<void> configure(OnboardingState next) async {
    await _serial(() => onboarding.save(next));
    if (next.step == OnboardingStep.complete) await incoming.markReady();
    _emit();
  }

  Future<void> chooseDirectory() async {
    final path = await pickDirectory();
    if (path == null) return;
    final current = onboarding.state;
    await configure(
      OnboardingState(
        step: current.step,
        language: current.language,
        directory: path,
        device: current.device,
        skipped: current.skipped,
      ),
    );
  }

  void edit(String value) {
    draft = value;
    dirty = draft != documents[selectedId]!['text'];
    _emit();
  }

  Future<void> save() async {
    final id = selectedId;
    final text = draft;
    await _serial(() async {
      final next = {
        ...documents,
        id: {...documents[id]!, 'text': text},
      };
      await store.write({...await store.read(), 'documents': next});
      documents[id] = next[id]!;
      if (selectedId == id) dirty = draft != text;
    });
    error = null;
    await incoming.drain();
    _emit();
  }

  Future<void> discard() async {
    draft = documents[selectedId]!['text']!;
    dirty = false;
    await incoming.drain();
    _emit();
  }

  Future<void> receive(Uri uri) async {
    try {
      await incoming.receive(IncomingIntent.fromUri(uri));
      error = null;
    } catch (value) {
      error = value;
    }
    _emit();
  }

  Future<void> _dispatch(IncomingIntent intent) async {
    switch (intent.action) {
      case IncomingAction.showTasks:
        tab = 'tasks';
      case IncomingAction.openDocument:
        final document = documents[intent.value];
        if (document == null) {
          throw StateError('Unknown document ${intent.value}');
        }
        selectedId = intent.value!;
        draft = document['text']!;
        tab = 'documents';
      case IncomingAction.importFile:
        await _import(await importFile(intent.value!));
    }
  }

  Future<void> importPicked() async {
    if (dirty) throw StateError('Save or discard the draft before import');
    final file = await pickDocument(onboarding.state.directory);
    if (file != null) await _import(file);
    _emit();
  }

  Future<void> _import(ImportedDocument document) async {
    final id = 'import_${DateTime.now().microsecondsSinceEpoch}';
    await _serial(() async {
      final item = {'title': document.name, 'text': document.text};
      await store.write({
        ...await store.read(),
        'documents': {...documents, id: item},
      });
      documents[id] = item;
      selectedId = id;
      draft = document.text;
      dirty = false;
      tab = 'documents';
    });
  }

  Future<bool> prepare() async {
    try {
      if (dirty) await save();
      await _pending;
      return true;
    } catch (value) {
      error = value;
      _emit();
      return false;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _links?.cancel();
    await incoming.close();
    await _pending;
    await onboarding.close();
    await store.close();
    unawaited(_changes.close());
  }
}
