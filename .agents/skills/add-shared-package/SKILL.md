---
name: add-shared-package
description: 创建跨 App 的共享 Dart 或 Flutter package 并登记 workspace、公共 API 和测试。
---

## 目标
提取已有稳定复用边界，形成能独立测试的 package。

## 决策
只在单 App 使用时优先 shared；单 Feature 逻辑留在 Feature。选择纯 Dart 或 Flutter package，先写清公开 API 和依赖方向。

## 流程
1. 在 `packages/<name>` 创建 pubspec、lib 入口和 test，成员设置 `resolution: workspace`。
2. 将路径加入根 pubspec workspace，给消费方加依赖；确认成员发现包含新包。
3. 只从 barrel 导出稳定契约；IO 实现不泄漏底层类型到调用方。
4. 若需要 Freezed 等生成器，配置 annotation、generator、build_runner 和 part，运行生成。
5. 测试公开行为与错误边界，运行完整门禁。

## 核心规则
- 不反向导入 App，不用相对路径跨成员访问源码。
- 纯领域包不依赖 Flutter/IO；UI 包不装配业务仓库或路由。
- 共享 UI 优先增强 koi_ui；主题与自适应行为见 [UI 契约](../../../docs/architecture/ui-and-adaptive.md)，用 UI Lab 与实际宿主证明消费。
- 不因为目录名叫 common 就把全部工具和业务状态塞进共享包。
- 不存在 package 子命令时按本流程完成，不能虚构脚手架命令。

## 验证
见 [Monorepo 契约](../../../docs/architecture/MONOREPO_ARCHITECTURE.md)。新增包必须出现在 generate/analyze/test/coverage 适用范围中，不能仅以旧成员全绿作为完成证据。
