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
KoiModuleRuntime<ShowcaseRepository> moduleRuntime(Ref ref) {
  throw UnimplementedError('Inject the module runtime in bootstrap.');
}

/// Bridge a mature Listenable into Riverpod's immutable dependency graph.
@riverpod
ModuleRuntimeState<ShowcaseRepository> moduleSnapshot(Ref ref) {
  final runtime = ref.watch(moduleRuntimeProvider);
  void changed() => ref.invalidateSelf();
  runtime.addListener(changed);
  ref.onDispose(() => runtime.removeListener(changed));
  return runtime.state;
}

@Riverpod(keepAlive: true)
class ModuleControls extends _$ModuleControls {
  @override
  String build() => '模块资源由会话拥有，共享事件总线由宿主拥有。';

  Future<void> setBetaConfigured(bool enabled) async {
    ref.read(showcaseServicesProvider).betaConfigured = enabled;
    final runtime = ref.read(moduleRuntimeProvider);
    if (runtime.state.session?.moduleId == 'beta') {
      try {
        await runtime.activate('beta', restart: true);
      } catch (_) {}
    }
    if (ref.mounted) {
      state = enabled ? 'Beta 已配置，可以重新切换' : 'Beta 暂未配置，切换会给出恢复提示';
    }
  }

  Future<void> select(String id) async {
    try {
      final runtime = ref.read(moduleRuntimeProvider);
      final session = await runtime.activate(id);
      if (ref.mounted) {
        state = '${session.moduleId} 已就绪，代次 ${session.generation}';
      }
    } on StaleModuleSessionException {
      // A newer selection owns the UI result.
    } catch (error) {
      if (ref.mounted) state = '模块切换失败：$error';
    }
  }

  Future<void> demonstrateStaleResult() async {
    final runtime = ref.read(moduleRuntimeProvider);
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
    await select(next.id);
    final message = await result;
    if (ref.mounted) state = message;
  }
}
