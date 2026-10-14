# 状态管理规范（Riverpod 3）

新项目使用注解式 Riverpod；已有独立状态机可在明确边界适配。状态只保留一个业务拥有者，provider 是其注入或只读投影。先从 [样例地图](../examples.md) 选择对应流程，再判断生命周期。

## UI 与状态拥有者

| 状态或资源 | 拥有者与重置时机 |
| --- | --- |
| 页面独占、离开即丢弃的筛选、显示模式、简单输入 | Widget State；离开后重置。TasksPage 的仅未完成筛选、MediaPage 的列表/网格切换是样例 |
| 查询、分页、提交及异步状态 | Feature Controller/Notifier；显式呈现失败、重试与过期结果 |
| 跨页面草稿、长期编辑 | 明确的 route/session 作用域；同时打开的实例使用稳定 editorId 或独立 scope，不能共享一个无参数全局草稿 |
| 持久化数据 | Repository 负责读取、保存和格式；Session/Controller 请求写入 |
| 服务、订阅、播放器、文本控制器 | 创建方释放；借用方只解除自己的监听 |

业务容器用 ConsumerWidget/ConsumerStatefulWidget 订阅 provider，事件使用 `read`。展示组件可以接收不可变数据与语义化回调。Widget 内允许布局、简单显示分支与格式呈现；可复用的业务规则才提取为纯函数或派生 provider。跨侧栏与正文共享的搜索、筛选继续由会话内 provider 持有。

ARCH010（字段超过 8）和 ARCH011（回调超过 4）提供数量 warning，用于审查职责、生命周期与接口；数量不代表架构错误，也不要求机械搬入 provider。依赖方向、domain 隔离与同步阻塞 IO 仍是 error。

Feature provider 统一放 `presentation/providers/`；纯展示 ViewModel 放 `presentation/models/`。`application/` 只承载业务用例、命令与编排，不建立另一套 provider。不要把 UI 语义放进 domain。

消费 scoped provider 的 Widget、路由、辅助函数与测试入口声明 `@Dependencies`（导入 `riverpod_annotation/experimental/scope.dart`）；引用生成声明名而非 provider 变量名。`@Dependencies` 是作用域消费元数据，Feature 的 `@riverpod` / `@Riverpod` 生成声明仍只放在 `presentation/providers`。嵌套 overrides 使用明确完整的列表，依赖链上的 provider 也要声明 `dependencies` 并 watch 可重绑定的资源。

## 异步状态不得被空列表掩盖

使用 `AsyncValue.when` 或模式匹配显示 loading/error/data。派生异步数据使用 `whenData` 保留原来的异步状态：

```dart
@riverpod
AsyncValue<List<Item>> visibleItems(Ref ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(itemsProvider).whenData(
    (items) => items.where((item) => item.matches(query)).toList(),
  );
}
```

Riverpod 3 的读取属性为 `.value`，不要复制旧版 `.valueOrNull`。`.value` 不是加载成功的证明；刷新时可能保留旧数据。只有产品明确接受“无数据按空处理”时才能提供空值回退，不能把网络失败或首次加载显示成空列表。

首次查询使用 AsyncValue 区分加载、失败与数据。刷新、分页、保存和提交使用显式的不可变展示状态（既有数据、操作中标记、操作失败），保留已有内容；不要调用 Riverpod 的内部 `copyWithPrevious` API。页面应明确刷新时保留旧内容还是显示 loading，以及错误是否可重试。测试首次加载失败、刷新失败和空数据三个不同场景。查询抛出的错误由 AsyncValue 承载；命令若返回 `Either<Failure,T>`，必须显式处理失败，不用空结果代替错误。

## 生命周期先于路径

注解 provider 默认自动销毁。把 state 移到 provider 并不保证切换路由后仍存在。

- 页面范围：默认 auto-dispose，离开后释放。
- 会话范围：由稳定的会话拥有者持有，切换账号/模块时 invalidate 或销毁对应 scope。
- 应用范围：确有需求才用 `@Riverpod(keepAlive: true)`，记录清理时机；不要给所有筛选和 family 实例永久保活。
- 重算也会销毁旧 provider 状态；`keepAlive` 不阻止依赖变化触发重建。

创建资源的一方负责释放。provider 自己创建 service、StreamController、订阅或 router 时，用 `ref.onDispose` 清理。通过 override 借用宿主共享服务时，只释放自己的订阅，不重复关闭宿主资源。`onDispose` 不用来触发其他 provider 的业务更新。

## 既有 ChangeNotifier / Stream 的适配

优先直接消费服务已有的 Stream。必须桥接 ChangeNotifier 时，在 provider 中注册一次监听并输出不可变快照；销毁时先移除监听再关闭 StreamController。避免传递并持续修改同一个 List/Map，订阅方无法可靠判断变化。

注入既有运行时、导航或播放对象时，provider 可以返回不可变资源句柄；资源本体属于创建方，不可把句柄当成自动跟踪内部字段的响应式状态。需要观察变化时显式使用不可变快照、Stream 或 Listenable 桥接；投影 provider 只清理自己的订阅。测试依赖重绑定和释放。

业务 Widget 不应自己为同一个外部服务重复建立 `addListener + setState` 数据通道。Flutter 自带动画/控制器等 Widget 本地资源仍按其生命周期使用。适配已有状态机不意味着所有新业务都应改用 ChangeNotifier。

## 已有 Session 的同步只读投影

Workbench 的 `workspaceSnapshotProvider` 首次同步读取 Session，再订阅其变化并使投影失效。重绑定和销毁解除旧订阅，绝不关闭借用的 Session，也不保留第二份可写业务状态。页面使用这个投影，无需 `.value ?? session.state`。兼容的 `workspaceStateProvider` 仍提供 AsyncValue；实际文件读取、网络查询等真实异步 IO 继续显式处理 AsyncValue。

Feature Lab 的 DraftController 使用 `draftId` 对应仓库、`editorId` 区分同时打开的编辑实例。宿主通过会话 ProviderScope 管理 keepAlive 草稿，返回旧路由可恢复编辑，销毁该 scope 清理实例。实例 key 在进入路由时建立，不能在 build 中随机生成。

`keepAlive` 与 family 只决定保活和实例参数，不自动赋予嵌套会话 scope 所有权。可在会话中替换的仓库/提交端口声明 `dependencies: []`，DraftController 声明这些依赖，消费 Widget 声明 `@Dependencies`。宿主从装配入口调用 `draftSessionOverrides(repositories: {'default': repository})`，把结果交给会话 ProviderScope；有提交能力时再传 `submissions`。该入口同时覆盖端口与整个 Controller family，确保父作用域已经读取同一实例时也不会借用父状态。用根 → 会话 A → 销毁 → 会话 B 的回归验证新仓库生效，并拒绝旧会话的迟到保存结果。

## 副作用、取消与过期结果

- 页面通过 `ref.listen` 处理 SnackBar、一次性导航；不要在 build 中发请求或保存数据。
- Notifier/service 管理提交、取消和跨资源编排；UI 只发语义化意图。
- `await` 之后写状态前，检查 `ref.mounted` 及操作序号/会话代次；provider 重建也要推进代次，保证较旧请求不会覆盖新结果。
- 取消订阅不等于取消 HTTP/进程。若依赖支持取消，需要同时调用实际取消机制；否则至少丢弃过期结果。
- provider 的自动重试策略要按查询/命令选择；有外部副作用的命令不能通过构建过程被隐式重复执行。

可注入仓库由 bootstrap override 提供；未装配即无法运行的依赖可以抛 `UnimplementedError`，不要静默返回假业务数据。

## 重建与性能

先保证状态不可变、订阅范围合理，再根据测量使用 `select` 或 family。family 只给出参数化实例，不保证只重建一个条目；如果每个实例都 watch 整个任务列表，它们仍会一起重算。选择稳定 id，并让选中值具备正确 equality；测试关键交互而不是假设优化成立。

## 测试

Widget 测试用 ProviderScope overrides 注入替身；provider 测试用 ProviderContainer，测试结束销毁。auto-dispose provider 需要在观察期间保持 listen 订阅，不能读取一次后假设它一直存活。

覆盖成功、失败、离开页面/会话销毁、并发结果逆序和重试。纯模型无需 Flutter；IO 集成测试可以使用临时目录，不访问用户真实数据或生产网络。禁止在 Widget build/provider 同步计算路径执行阻塞文件与进程 IO。
