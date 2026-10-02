import 'dart:async';

import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';
import 'package:module_showcase/features/module_capabilities/domain/text_analysis.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'analysis_providers.g.dart';

@Riverpod(keepAlive: true)
AnalysisSession analysisSession(Ref ref) =>
    throw UnimplementedError('Page composition owns this session');
@riverpod
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
