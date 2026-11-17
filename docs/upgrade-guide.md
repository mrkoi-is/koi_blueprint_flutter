# 下游工程升级指南

安全升级入口正在发布验收中，可规划受管工具、共享包、App 文件及本轮支持的依赖变更。无法重现基线的 App 变更、未知依赖变更、删除和未经审核的旧引用会阻断；不能把部分更新当作完整版本升级。在独立副本试用，使用新蓝图源码中的 CLI：

```sh
python3 /path/to/new-blueprint/blueprint.py upgrade plan --app apps/my_app --source /path/to/new-blueprint --output /tmp/koi-upgrade-plan.json
python3 /path/to/new-blueprint/blueprint.py upgrade apply --app apps/my_app --plan /tmp/koi-upgrade-plan.json
python3 /path/to/new-blueprint/blueprint.py upgrade rollback --app apps/my_app --transaction <transaction-id>
```

计划输出必须位于目标 workspace 外；apply 会重新计算计划，拒绝过期计划与未解决冲突。对指导/工具文件，计划可通过 `--resolutions <json文件>` 接收按路径映射的 `choice`（`keep-local` 或 `merged`）与审核后 `currentSha256`。旧引用文件没有基线时，人工比较后可用 `take-upstream` 并同时提供 `currentSha256` 和 `targetSha256`。每次更改受审文件后必须重新规划。事务备份位于蓝图数据目录的 upgrades 子目录；回滚会先检查文件是否被后续编辑，不会覆盖冲突。

`v0.3.0-rc.1` 整合了新的依赖版本，从两个历史 CI 基线直接升级时会报告 root/App/koi_core 的依赖冲突，需要人工审阅迁移。该版本的 `Migration boundary` CI 只验证明确冲突、拒绝应用及工程/来源记录不变，不表示自动升级和升级后运行成功。不要删除冲突或修改基线摘要绕过检查；具体范围见 [候选版本记录](https://github.com/mrkoi-is/koi_blueprint_flutter/blob/v0.3.0-rc.1/docs/releases/v0.3.0-rc.1.md)。

原有只读报告继续可用：

`upgrade-report` 只比较文件和来源，不修改工程，也不执行依赖解析。先确认目标蓝图源码、提交与工作区 dirty 状态，再在现有工程中运行：

```sh
python3 blueprint.py upgrade-report --app apps/my_app --source /path/to/koi_blueprint_flutter > upgrade-report.json
```

报告中的 `upstreamChanges` 是本地仍保持创建基线、但上游已变化的文件；`localChanges` 是仅下游修改；`conflicts` 是双方改动不同；`alreadyApplied` 表示下游已经采用与新上游相同的内容；`unchanged` 无需处理。`newCapabilities` 只表示目标蓝图提供了新配方，不表示应全部安装。`capabilityUpdates` 提醒能力版本或翻译来源变化。

schema 2 的指导文件若缺少创建时基线，会出现在 `untrackedGuidance`：`path`、`source`、`status: NO_BASELINE`、`localExists` 和两侧当前摘要。即使两侧当前内容相同，也不能归为未变化或已应用；本地缺文件时当前摘要为 null。这些项需要人工比较，报告不会覆盖文件、补造历史基线或修改 blueprint.json。新生成项目的指导文件复用 `managedFiles` 和内容基线，并登记原始源摘要与生成后摘要。

处理时保留一份可回退的现有工程，在单独分支或副本中逐项应用上游变化。先看每个 `conflicts` 的实际内容和业务目的，再决定合并方式；不要用报告中的摘要代替代码审阅。随后检查 App 装配入口、原生 runner、根 `pubspec.yaml` 与锁文件，并运行 `python3 blueprint.py validate`、所选平台构建及实际运行。将本轮报告、命令、源码摘要、构建清单和设备结果一并归档。

schema 1 或缺少来源元数据的旧工程无法做可信三方比较。报告会返回 `manualMigration` 步骤。此时从目标蓝图另建一个 schema 2 工程，保持旧工程不变，手工对照模板、App 装配、平台 runner、依赖与业务文件；将业务改动迁入新副本并验证后，才为确知来源的文件建立基线。不能只改 `blueprint.json` 的 schema 数字，也不能把新模板整体覆盖旧工程。

已安装能力若因用户编辑受管文件而拒绝重新安装，先运行只读报告并保存冲突文件。保留用户修改，在新副本内合并对应配方、ARB 和原生配置，验证后再继续。`capability add --dry-run` 可先列出文件和依赖变更；安装器不会自动解决冲突、卸载能力或升级业务数据。
