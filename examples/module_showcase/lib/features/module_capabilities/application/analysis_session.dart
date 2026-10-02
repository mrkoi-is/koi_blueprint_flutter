import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/domain/text_analysis.dart';

/// Two compiled implementations share one typed capability contract. The host
/// retains its router; this composition contributes only an embeddable page.
final class AnalysisSession {
  AnalysisSession() {
    runtime = KoiModuleRuntime(
      KoiModuleCatalog([
        KoiModule<TextAnalysisEngine>(
          id: 'words',
          routes: const [],
          navigation: const [],
          capabilities: const {'text.analyze.words'},
          createSession: (context) => _create(context, characters: false),
        ),
        KoiModule<TextAnalysisEngine>(
          id: 'characters',
          routes: const [],
          navigation: const [],
          capabilities: const {'text.analyze.characters'},
          checkAvailability: () => charactersEnabled
              ? const CapabilityAvailability.available()
              : const CapabilityAvailability.unavailable(
                  'Character engine is disabled in configuration',
                ),
          createSession: (context) => _create(context, characters: true),
        ),
      ]),
    );
  }
  late final KoiModuleRuntime<TextAnalysisEngine> runtime;
  bool charactersEnabled = true;
  bool failNextCreation = false;
  int closedEngines = 0;
  TextAnalysisEngine _create(
    ModuleSessionContext context, {
    required bool characters,
  }) {
    final engine = _ScopedEngine(context, characters);
    context.onDispose(() {
      engine.closed = true;
      closedEngines++;
    });
    if (failNextCreation) {
      failNextCreation = false;
      throw StateError('Injected engine initialization failure');
    }
    return engine;
  }

  Future<void> activate(String id, {bool restart = false}) async {
    await runtime.activate(id, restart: restart);
  }

  Future<TextAnalysis> analyze(String text) {
    final current = runtime.state.session;
    if (current == null) throw StateError('Choose an available engine');
    return current.capability.analyze(text);
  }

  Future<void> close() => runtime.disposeAsync();
}

final class _ScopedEngine implements TextAnalysisEngine {
  _ScopedEngine(this.context, this.characters);
  final ModuleSessionContext context;
  final bool characters;
  bool closed = false;
  @override
  Future<TextAnalysis> analyze(String text) async {
    context.ensureActive();
    if (closed) throw StateError('Engine closed');
    final count = characters
        ? text.runes.length
        : text
              .trim()
              .split(RegExp(r'\s+'))
              .where((word) => word.isNotEmpty)
              .length;
    return TextAnalysis(
      context.moduleId,
      characters ? 'Unicode code points' : 'whitespace-separated words',
      count,
    );
  }
}
