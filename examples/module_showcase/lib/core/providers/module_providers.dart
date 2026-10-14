import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/core/services/showcase_services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

part 'module_providers.g.dart';

@Riverpod(keepAlive: true)
HostShowcaseServices showcaseServices(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject shared services');

/// Bootstrap owns runtime shutdown; this provider only injects it.
@Riverpod(keepAlive: true)
({KoiModuleRuntime<ShowcaseRepository> runtime}) moduleRuntime(Ref ref) {
  throw UnimplementedError('Inject the module runtime in bootstrap.');
}

/// Bridge a mature Listenable into Riverpod's immutable dependency graph.
@riverpod
ModuleRuntimeState<ShowcaseRepository> moduleSnapshot(Ref ref) {
  final runtime = ref.watch(moduleRuntimeProvider).runtime;
  void changed() => ref.invalidateSelf();
  runtime.addListener(changed);
  ref.onDispose(() => runtime.removeListener(changed));
  return runtime.state;
}

@Riverpod(keepAlive: true)
class ModuleControls extends _$ModuleControls {
  int _generation = 0;
  @override
  String build() {
    ref.watch(moduleRuntimeProvider);
    ref.watch(showcaseServicesProvider);
    ref.onDispose(() => _generation++);
    return '模块资源由会话拥有，共享事件总线由宿主拥有。';
  }

  Future<void> setBetaConfigured(bool enabled) async {
    final generation = ++_generation;
    ref.read(showcaseServicesProvider).betaConfigured = enabled;
    final runtime = ref.read(moduleRuntimeProvider).runtime;
    if (runtime.state.session?.moduleId == 'beta') {
      try {
        await runtime.activate('beta', restart: true);
      } catch (_) {}
    }
    if (ref.mounted && generation == _generation) {
      state = enabled ? 'Beta 已配置，可以重新切换' : 'Beta 暂未配置，切换会给出恢复提示';
    }
  }

  Future<void> select(String id) => _select(id, ++_generation);

  Future<void> _select(String id, int generation) async {
    try {
      final runtime = ref.read(moduleRuntimeProvider).runtime;
      final session = await runtime.activate(id);
      if (ref.mounted && generation == _generation) {
        state = '${session.moduleId} 已就绪，代次 ${session.generation}';
      }
    } on StaleModuleSessionException {
      // A newer selection owns the UI result.
    } catch (error) {
      if (ref.mounted && generation == _generation) state = '模块切换失败：$error';
    }
  }

  Future<void> demonstrateStaleResult() async {
    final generation = ++_generation;
    final runtime = ref.read(moduleRuntimeProvider).runtime;
    final session = runtime.state.session;
    if (session == null) return;
    final next = runtime.catalog.modules.firstWhere(
      (module) => module.id != session.moduleId,
    );
    // Handle the error immediately so cancellation cannot become unhandled.
    final result = session.capability
        .loadMessage(delay: const Duration(milliseconds: 600))
        .then<String>(
          (value) => '过期结果错误地被接受：$value',
          onError: (Object error) {
            if (error is StaleModuleSessionException) return '旧会话结果已拒绝';
            return '读取失败：$error';
          },
        );
    await _select(next.id, generation);
    if (!ref.mounted || generation != _generation) return;
    final message = await result;
    if (ref.mounted && generation == _generation) state = message;
  }
}
