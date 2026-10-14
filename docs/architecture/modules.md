# 业务模块与宿主装配

独立业务 module 用于有清楚的依赖、会话或复用边界的业务域。普通页面仍放 App 的 Feature；无需为每个功能创建 package。实际代码通过 [样例地图](../examples.md) 中的模块契约与模块宿主入口查看。

## 公开接口

| 接口 | 职责 |
| --- | --- |
| `KoiModule<T>` | 描述 id、routes、navigation 和 `createSession` 工厂；路由/导航列表不可变 |
| `ModuleNavigationItem` | 模块公开导航 id、label、location，供宿主呈现 |
| `KoiModuleCatalog<T>` | 不可变模块组合；校验重复/空模块 ID、导航 ID、重复路由路径和名称 |
| `KoiModuleRuntime<T>` | `activate(id)` 串行处理会话切换，公开当前会话/切换/错误状态 |
| `ModuleSessionContext` | 会话代次、`isActive`、`guard(future)`、`onDispose(callback)` 与 `disposeAsync()` |
| `ModuleSession<T>` | 会话上下文与对宿主暴露的 capability |

不存在全局可变 registry。宿主在组合根构造模块目录与共享服务；模块工厂通过闭包/构造器获得公共依赖，不能去宿主源码中查找全局实例。

## 路由与依赖注入

模块只公开自身类型化路由、导航描述和 session 工厂。宿主一次合并 catalog.routes 并创建稳定 GoRouter，切换会话通过状态刷新/重定向控制可访问页面，不重建整套路由对象。导航项是否指向实际页面、参数是否合法和壳层路由冲突，仍需宿主测试。

模块之间不导入实现；确有跨域能力时放到共享契约 package，由宿主注入。Showcase 中的公共 repository 契约是这种协作方式的示例，不是所有生成 module 都必须依赖的固定业务包。

## 会话与资源生命周期

1. `activate(id)` 先使旧会话结果失效，再等待拥有的旧资源清理并创建新会话。
2. 用 `context.onDispose` 登记模块创建的订阅、取消 token、控制器等；清理按登记逆序执行。
3. 通过 `context.guard(pending)` 等待异步操作时，旧会话完成会抛 `StaleModuleSessionException`。它只拒绝结果，本身不会取消 Future。
4. 外部操作需要取消时，在开始工作前注册实际取消机制；捕获取消/过期状态，不能把它写回新会话。
5. 宿主退出应 `await runtime.disposeAsync()`，随后才关闭宿主共享设施。同步 `dispose()` 不能作为已等待异步清理的证据。

session 工厂必须有界并注册取消/关闭逻辑。切换转换串行等待旧工厂/清理；旧工厂若永不完成，后续激活也会等待，`guard` 无法替代超时或底层取消。

runtime 只拥有模块 session，不拥有所有注入的共享设施。会话创建失败进入错误状态，UI 必须能显示或重试；不能假定旧会话自动恢复。重复异步销毁保持同一清理过程，每个清理失败都会记录，不能因一个失败遗漏其余清理。

## 生成与接入

```sh
python3 blueprint.py module reporting --workspace . --dry-run
python3 blueprint.py module reporting --workspace .
```

确认生成成员已登记，再添加宿主对该模块的依赖、catalog 组合、navigation/route 入口和 provider override。脚手架产生公共结构，业务 capability 和宿主装配仍应按产品需要完成，不复制 Showcase 的 alpha/beta 身份。最小模板公开 `createMinimalModule()` 和 `MinimalModuleRoute`，生成后使用对应的新名称。

## 验证

契约测试覆盖重复 ID/路由、未知模块、成功切换、资源释放、重复 dispose、创建失败与快速连续切换。宿主测试覆盖路由可达和参数、provider 注入、错误呈现、旧异步结果被拒绝，以及模块退出后共享服务仍可用。

仅通过 Dart/Flutter 测试不意味着真实原生插件或网络会话已验证；这些实现分别补集成证据。

同一个模块的普通导航复用当前会话；账号或租户发生变化时使用 `activate(id, restart: true)`，即使模块 ID 不变也释放旧会话、创建新会话。

模块公开入口只显式导出路由类型（`show SomeRoute`）和装配工厂；不要重导出生成的 `$appRoutes`，以免与宿主或其他模块的路由注册表发生符号冲突。路由贡献由 catalog 组合。
