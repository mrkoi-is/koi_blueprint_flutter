---
name: add-feature-module
description: 在现有 App 或业务 module 新增 presentation、api 或 local Feature 并完成注入、导航和测试。
---

## 目标
新增一个符合当前分层的业务 Feature，包含可验证的页面与状态/数据边界。

## 决策
纯展示选 `presentation`；远程仓库选 `api`；本地数据/会话选 `local`。独立业务 package 用 `add-business-module`，不要把普通页面过早拆成 module。

## 流程
1. 读 [Feature 契约](references/feature-contract.md)，确认目标成员和邻近实现。
2. 运行 `python3 blueprint.py feature <app_or_module_path> <name> --kind <kind> --dry-run`，再实际生成。
3. 用真实模型替换示例，明确状态拥有者、错误语义和仓库接口；需要 IO 和编排时同时保留 data/application。
4. 在宿主 bootstrap/provider 中注入实现，加入类型化路由或宿主导航，避免第二套 router。
5. 增加成功/失败及关键生命周期测试，执行受影响测试与完整门禁。

## 核心规则
- 参照 [Feature Lab](../../../docs/examples.md)；认证专用行为参照 [认证样例](../../../docs/examples.md)。
- domain 纯 Dart，presentation 不直接 IO；Feature provider 统一放 presentation/providers。
- 业务容器通过 provider 取数，展示 Widget 可以用不可变 props 和回调。
- 页面先消费 [DESIGN](../../../DESIGN.md) 与 UI Lab 的标准 Flutter 组件主题；跨页面外观统一在 koi_ui 修正，标准组件能表达时不新增平行控件。
- 脚手架的示例数据不是已接通的真实 API 或持久化。

## 验证
除 analyze 外，验证页面可从宿主到达、依赖已注入、加载/失败/空态可区分、离开后资源释放。完整规则见 [状态规范](../../../docs/architecture/state-management.md)。
