---
name: workspace-init
description: 从 Koi 蓝图创建独立 Flutter workspace 并验证名称、平台、依赖和 AI 入口。
---

## 目标
创建能独立运行和继续开发的新 workspace，保留蓝图架构和 AI 入口。

## 决策
先确定项目名、目标目录、组织标识、平台与 minimal/workbench 模板。所有新项目默认接入 koi_ui；minimal 保持最小业务，workbench 加入本地资料/媒体/任务样例。新项目默认不包含认证演示。平台生成与平台构建是两项验收。

## 流程
1. 阅读 [初始化契约](references/initialization-contract.md)，核对输入和目标目录。
2. 调用 `python3 blueprint.py create <name> --output <directory> --org <org> --platforms <platforms> --template <minimal|workbench> --dry-run`。
3. 确认输出符合任务后执行同命令去掉 `--dry-run`；非空目标报错时换目录，不覆盖用户文件。
4. 进入目标 workspace，按 [创建项目](../../../docs/new-project.md) 解析依赖、验证并构建目标平台。
5. 交付项目位置、App 名、平台、实际检查结果和剩余业务装配项。

## 核心规则
- workspace 成员只以根 pubspec 为准，成员使用 `resolution: workspace`。
- 身份/平台元数据在 `blueprint.json`，不另建成员清单。
- 使用匹配 `.fvmrc` 的 SDK；生成器兼容组合整体维护。
- 不将原作者本机路径、其他私有仓库或登录凭证作为新项目的依赖。

## 验证
运行 `python3 blueprint.py validate` 和选定平台的 `build`。Windows 用 `py -3`。检查改名后的 imports、构建目标、AI 引用和测试；只有目录生成完成时，不宣称新项目运行已验证。
