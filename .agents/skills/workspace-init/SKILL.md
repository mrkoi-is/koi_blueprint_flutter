---
name: workspace-init
description: 从 Koi 蓝图创建独立 Flutter workspace 并验证名称、平台、依赖和 AI 入口。
---

## 目标
创建能独立运行和继续开发的新 workspace，保留蓝图架构和 AI 入口。

## 决策
先确定项目名、目标目录、组织标识、平台与 minimal/workbench 模板，再按实际需求选择版本化 JSON 中的语言、能力、品牌和构建 profile。所有新项目默认接入 koi_ui；minimal 保持最小业务，workbench 加入本地资料/媒体/任务样例。未选择的能力不继承其运行依赖。新项目默认不包含认证演示。平台生成与平台构建是两项验收。

## 流程
1. 阅读 [初始化契约](references/initialization-contract.md)，核对输入和目标目录。
2. 调用 `python3 blueprint.py create <name> --output <directory> --config <json> --dry-run`；没有配置文件时使用原有 `--org`、`--platforms`、`--template` 参数。重复字段冲突会报错，不靠隐式覆盖。
3. 确认输出符合任务后执行同命令去掉 `--dry-run`；非空目标报错时换目录，不覆盖用户文件。
4. 进入目标 workspace，运行 `capability list --app apps/<name>_app` 核对已安装能力。后续能力先用 `capability add <id> --app ... --config <json> --dry-run` 审阅文件、依赖和原生接线，再执行安装；受管文件冲突通过只读报告人工迁移。
5. 按 [创建项目](../../../docs/new-project.md) 安装或指定固定 SDK，执行 doctor、devices、run、validate；用匹配 host 的 `build --profile <name>` 生成身份清单，需安装包时再 `package --profile <name>`。构建通过和设备实际运行分别记录。
6. 交付项目位置、App 名、平台、能力配置、来源摘要、实际检查结果和剩余业务装配项。

## 核心规则
- workspace 成员只以根 pubspec 为准，成员使用 `resolution: workspace`。
- `blueprint.json` schema 2 记录来源链、配置摘要、能力版本和受管文件基线；根 pubspec 仍是成员单一来源。递归生成与无 Git 导出也保留内容身份。
- 下游升级只运行 `upgrade-report --app ... --source ...` 做三方只读比较；不自动覆盖业务代码或伪造旧工程基线。
- 使用匹配 `.fvmrc` 的 SDK；生成器兼容组合整体维护。
- 不将原作者本机路径、其他私有仓库或登录凭证作为新项目的依赖。

## 验证
创建时自动检查继承 AI 资产；运行 `python3 blueprint.py doctor --purpose validate`、`python3 blueprint.py validate` 和选定平台的 `build`。Windows 用 `py -3`。检查改名后的 imports、能力依赖与原生接线、构建目标、AI 引用和测试；只有目录生成完成时，不宣称新项目运行已验证。构建、打包、设备运行、安装与移除各自保留独立证据。
