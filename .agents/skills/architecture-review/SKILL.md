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
- data/application 共存不是缺陷。ARCH010/ARCH011 统计字段/回调并返回 warning，用于审查职责、生命周期与接口，不强迫局部筛选/显示模式迁入 provider。依赖方向、domain 隔离、模块入口与阻塞 IO 仍为 error；ARCH012 已退役。
- 旧数量预算例外继续可读，失效/超预算为 warning；硬规则例外失效和非法配置保持失败语义。JSON 的 ok 只依赖 error。
- 同时打开的编辑实例须隔离；Session 投影不得复制业务状态，协作者只通过内部 access 读取最新值并提交同步变换。
- 新生成指导文件复用 managedFiles 的内容基线与源摘要；旧 schema 2 缺基线以 untrackedGuidance/NO_BASELINE 报告，不补造或覆盖。
- family 不保证局部重建，覆盖率不证明平台运行，文档不证明实现。
- 架构/Skill/模板/测试应同改；失效路径和未登记成员必须指出。

消费 scoped provider 时，为 Widget、路由和辅助函数补 `@Dependencies`，依赖链声明 `dependencies`。Riverpod lint 3.1.9 的 15 条已全部启用；不使用 lint ignore 绕过。生成注解与消费元数据的边界见状态管理规范。

## 验证
报告实际运行过的命令和平台；未运行的检查标为未执行。修复后复测原始触发场景，避免只报告 lint 通过。
