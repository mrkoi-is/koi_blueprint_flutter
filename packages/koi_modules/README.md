# koi_modules

可选业务模块装配包。普通 App 可以只使用 Feature；只有独立依赖、路由或会话边界需要 module。

宿主显式构造 `KoiModuleCatalog<T>`，模块贡献 `id`、go_router 路由、导航和 `createSession` 工厂。`T` 是宿主约定的公开能力，可以是共享契约，也可以是无需服务的 `Object`。包不包含全局 registry，也不导入业务实现。

`KoiModuleRuntime.activate(id)` 先使旧结果失效，再串行等待旧资源关闭和新会话初始化。重复选中当前模块复用会话；账号或租户变化时，宿主应调用 `activate(id, restart: true)`。稳定的宿主 GoRouter 可以通过 runtime 的 Listenable 刷新访问控制；具体重定向属于宿主。

资源通过 `ModuleSessionContext.onDispose` 登记，按逆序、恰好一次关闭。`guard(future)` 拒绝过期结果，但不会取消底层工作：模块仍须登记 timer、subscription、cancel token 等实际取消/关闭动作。开始新工作前用 `ensureActive()`；结果写回前经 `guard` 等待。共享基础设施由宿主拥有，模块只关闭自己创建的资源。

初始化和关闭按顺序执行，因此工厂必须有界完成。无法取消、永久不完成的工厂会阻塞后续切换。初始化失败会关闭已登记资源、保留错误并清空 active session；不会自动恢复旧会话。多个关闭失败会聚合，剩余回调仍执行。宿主退出应 `await runtime.disposeAsync()` 后再关闭共享服务；Flutter 同步 `dispose()` 仅启动这个异步过程。

示例见 `examples/module_showcase`；无业务契约的生成模板见 `examples/minimal_module`。运行本包测试：

```sh
../../tool/flutterw test --no-pub --coverage
```
