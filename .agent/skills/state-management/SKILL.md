---
name: state-management
description: 按 Koi Riverpod 3 契约实现页面、异步状态、派生计算、依赖注入与生命周期。
---

## 目标
让状态有唯一拥有者、异步失败可观察，资源生命周期可测试。

## 决策
先区分 Widget 本地状态、页面状态、会话状态、应用状态。普通展示 Widget 不必变成 Consumer；保留受测的既有状态机时在 provider 边界适配。

## 流程
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
- data/application 可以共存；展示 props 和本地 setState 都有合法用途。
- 工作区三视图共用会话，resize 不重建文本/媒体控制器；参照 [UI 与自适应](../../../docs/architecture/ui-and-adaptive.md) 和 Workbench。

## 验证
参照 [Feature Lab](../../../docs/examples.md) 和认证 provider 测试。未测取消与释放时，不宣称生命周期安全。
