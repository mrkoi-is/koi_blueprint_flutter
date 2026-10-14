import 'dart:async';

import 'package:koi_core/koi_core.dart';

import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';
import 'package:module_showcase/features/module_capabilities/domain/text_analysis.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'analysis_providers.g.dart';

@Riverpod(dependencies: [])
AnalysisSession analysisSession(Ref ref) {
  final owner = AnalysisSession();
  final unregister = CapabilityLifecycle.instance.register(
    prepare: () async => true,
    close: owner.close,
  );
  ref.onDispose(() {
    unregister();
    unawaited(owner.close());
  });
  unawaited(
    owner.activate('words').catchError((Object error) {
      // Runtime publishes current initialization errors in analysisState.
      // Superseded or disposed startup requests must not escape as zone errors.
    }),
  );
  return owner;
}

@Riverpod(dependencies: [analysisSession])
Stream<ModuleRuntimeState<TextAnalysisEngine>> analysisState(Ref ref) {
  final owner = ref.watch(analysisSessionProvider);
  final controller = StreamController<ModuleRuntimeState<TextAnalysisEngine>>();
  void changed() => controller.add(owner.runtime.state);
  owner.runtime.addListener(changed);
  changed();
  ref.onDispose(() {
    owner.runtime.removeListener(changed);
    unawaited(controller.close());
  });
  return controller.stream;
}

/// 探测结果、配置草稿和操作错误由 provider 拥有。
@Riverpod(dependencies: [analysisSession])
class AnalysisCommands extends _$AnalysisCommands {
  int _generation = 0;
  @override
  ({TextAnalysis? result, Object? error, int revision, String input}) build() {
    ref.watch(analysisSessionProvider);
    ref.onDispose(() => _generation++);
    return (
      result: null,
      error: null,
      revision: 0,
      input: 'One shared contract',
    );
  }

  Future<void> select(String id) => _perform(
    () => ref.read(analysisSessionProvider).activate(id, restart: true),
  );
  Future<void> setCharacters(bool value) => _perform(() async {
    final owner = ref.read(analysisSessionProvider);
    owner.charactersEnabled = value;
    if (owner.runtime.state.session?.moduleId == 'characters') {
      await owner.activate('characters', restart: true);
    }
  });
  void setFailNext(bool value) {
    ref.read(analysisSessionProvider).failNextCreation = value;
    state = (
      result: state.result,
      error: state.error,
      revision: state.revision + 1,
      input: state.input,
    );
  }

  void setInput(String value) {
    _generation++;
    state = (
      result: null,
      error: null,
      revision: state.revision + 1,
      input: value,
    );
  }

  Future<void> analyze() => _perform(() async {
    final owner = ref.read(analysisSessionProvider);
    final session = owner.runtime.state.session;
    final generation = _generation;
    final result = await owner.analyze(state.input);
    if (!ref.mounted ||
        generation != _generation ||
        session != owner.runtime.state.session) {
      return;
    }
    state = (
      result: result,
      error: null,
      revision: state.revision + 1,
      input: state.input,
    );
  });
  Future<void> _perform(Future<void> Function() action) async {
    final generation = ++_generation;
    state = (
      result: null,
      error: null,
      revision: state.revision + 1,
      input: state.input,
    );
    try {
      await action();
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = (
        result: null,
        error: error,
        revision: state.revision + 1,
        input: state.input,
      );
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    state = (
      result: state.result,
      error: null,
      revision: state.revision + 1,
      input: state.input,
    );
  }
}
