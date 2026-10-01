---
name: architecture-review
description: 对 Koi workspace 审查依赖边界、状态归属、模块生命周期和架构门禁证据。
---

## 目标
给出可复现的架构偏离及影响，区分有效例外、历史实现与真正缺陷。

## 决策
先确认新项目/存量迁移、目标平台与请求范围。普通实现审查不自动扩大成发布或合规审查。

## 流程
1. 读 [架构契约](../../../docs/architecture/ARCHITECTURE.md)，检查工作区变化与成员清单。
2. 抽样一条从宿主入口到 Feature/provider/repository 的真实链路，对照对应 Skill 与样例。
3. 检查 domain/IO/UI、App/package、module 横向边界，以及 bootstrap 资源拥有者。
4. 检查 loading/error、取消与迟到结果、provider 生命周期、稳定 router、模块会话隔离。
5. 执行适用只读检查，按严重性记录路径/行号、触发条件、影响和修复建议。

## 核心规则
- data/application 共存不是缺陷；展示 props、本地 UI state 和有理由的适配器也是合法实现。
- family 不保证局部重建，覆盖率不证明平台运行，文档不证明实现。
- 架构/Skill/模板/测试应同改；失效路径和未登记成员必须指出。

## 验证
报告实际运行过的命令和平台；未运行的检查标为未执行。修复后复测原始触发场景，避免只报告 lint 通过。
