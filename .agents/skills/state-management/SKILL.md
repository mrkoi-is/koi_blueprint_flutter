---
name: state-management
description: 按 Koi Riverpod 3 契约实现页面、异步状态、派生计算、依赖注入与生命周期。
---

## 目标
让状态有唯一拥有者、异步失败可观察，资源生命周期可测试。

## 决策
先区分 Widget 本地状态、页面状态、会话状态、应用状态。普通展示 Widget 不必变成 Consumer；保留受测的既有状态机时在 provider 边界适配。

## 流程
修复已有行为先沿 [任务起点](../../../docs/examples.md#已有行为修复的起点) 读取页面、状态拥有者和目标测试。已存在的测试足够覆盖时直接复用；新增测试结构或验证策略时才另选 testing-scaffold。端口、实现和装配按问题继续追踪，不把完整阅读表当作前置条件。

1. 读 [状态管理规范](../../../docs/architecture/state-management.md)，重点核对异步状态与生命周期。
2. 新 provider 用 riverpod_generator；决定 auto-dispose、会话 scope 或 keepAlive，并说明重置时机。
3. 数据通过 repository/端口，UI 通过 watch；事件使用 read，UI 副作用使用 listen。
4. 派生 AsyncValue 用 whenData 保留 loading/error；不要用空集合掩盖失败。
5. 用 overrides 验证成功/失败/逆序请求/销毁；需要时再测 select/family 的重建范围。

## 核心规则
- Riverpod 3 使用 `.value`，不复制 `.valueOrNull`；有值也可能仍处于刷新/错误状态。
- provider 默认 auto-dispose；放进 provider 不代表能跨路由保存。
- provider 释放自己创建的资源，借用共享资源只解除自己的订阅。
- await 后检查 mounted 与操作代次，旧结果不能覆盖新状态。
- 页面独占、离开即丢弃的筛选、显示模式和简单输入留在 Widget；查询/分页/提交进入 Controller。跨页面草稿显式使用 route/session scope 与稳定 editorId，同时打开的实例隔离。持久化归 Repository，资源由创建方释放。
- 既有 Session 的同步只读投影首次读当前状态、订阅变化、重绑定解除旧订阅；不复制可写业务状态，也不关闭借用的 Session。真实异步 IO 保留 AsyncValue。
- keepAlive/family 不自动赋予嵌套会话归属：端口声明 scoped dependencies，Controller 与消费 Widget 接续依赖链；Draft 使用装配入口的 draftSessionOverrides 同时覆盖端口和 Controller family。测试父作用域预先读取实例后，会话销毁再建仍使用新仓库，不能只测无 parent 的容器。
- ARCH010/ARCH011 的数量是 warning，审查职责与生命周期，不机械迁入 provider。
- 新增展示内容或改变布局/控件交互前，先在本 feature 和 packages/koi_ui/lib 检索任务名词。修复已有事件接线或 provider 实例参数时先定位对应回调，不要求遍历 UI 组件目录。已经有的面板、属性行、工具栏和探查函数直接调用。
- 同级内容侧栏/详情复用 koi_ui 的 KoiPanel；宿主持有跨抽屉/内联切换的滚动恢复范围，不把稳定 router 等同于局部滚动自动保持。
- 工作区三视图共用会话，resize 不重建文本/媒体控制器；参照 [UI 与自适应](../../../docs/architecture/ui-and-adaptive.md) 和 Workbench。

消费 scoped provider 时，为 Widget、路由和辅助函数补 `@Dependencies`，依赖链声明 `dependencies`。不使用 lint ignore 绕过作用域约束。生成注解与消费元数据的边界见状态管理规范。

## 验证
参照 [Feature Lab](../../../docs/examples.md) 和认证 provider 测试。未测取消与释放时，不宣称生命周期安全。
