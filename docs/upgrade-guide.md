# 下游工程只读升级指南

`upgrade-report` 只比较文件和来源，不修改工程，也不执行依赖解析。先确认目标蓝图源码、提交与工作区 dirty 状态，再在现有工程中运行：

```sh
python3 blueprint.py upgrade-report --app apps/my_app --source /path/to/koi_blueprint_flutter > upgrade-report.json
```

报告中的 `upstreamChanges` 是本地仍保持创建基线、但上游已变化的文件；`localChanges` 是仅下游修改；`conflicts` 是双方改动不同；`alreadyApplied` 表示下游已经采用与新上游相同的内容；`unchanged` 无需处理。`newCapabilities` 只表示目标蓝图提供了新配方，不表示应全部安装。`capabilityUpdates` 提醒能力版本或翻译来源变化。

处理时保留一份可回退的现有工程，在单独分支或副本中逐项应用上游变化。先看每个 `conflicts` 的实际内容和业务目的，再决定合并方式；不要用报告中的摘要代替代码审阅。随后检查 App 装配入口、原生 runner、根 `pubspec.yaml` 与锁文件，并运行 `python3 blueprint.py validate`、所选平台构建及实际运行。将本轮报告、命令、源码摘要、构建清单和设备结果一并归档。

schema 1 或没有受管文件基线的旧工程无法做可信三方比较。报告会返回 `manualMigration` 步骤。此时从目标蓝图另建一个 schema 2 工程，保持旧工程不变，手工对照模板、App 装配、平台 runner、依赖与业务文件；将业务改动迁入新副本并验证后，才为确知来源的文件建立基线。不能只改 `blueprint.json` 的 schema 数字，也不能把新模板整体覆盖旧工程。

已安装能力若因用户编辑受管文件而拒绝重新安装，先运行只读报告并保存冲突文件。保留用户修改，在新副本内合并对应配方、ARB 和原生配置，验证后再继续。`capability add --dry-run` 可先列出文件和依赖变更；安装器不会自动解决冲突、卸载能力或升级业务数据。
