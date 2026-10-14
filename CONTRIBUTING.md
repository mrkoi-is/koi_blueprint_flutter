# 参与贡献

先读 [AI Quickstart](docs/ai-quickstart.md) 和 [架构契约](docs/architecture/ARCHITECTURE.md)。人和 AI 使用相同的 CLI、边界与验证标准。

## 修改流程

1. 查看工作区状态，保留与本次任务无关的修改。
2. 描述可观察的问题和目标行为；跨层变化先写明依赖方向与生命周期。
3. 修改源码；涉及公共接口、脚手架或架构时，同步样例、Skill 与文档。
4. 运行受影响测试，再运行 `python3 blueprint.py validate`。目标平台构建单独记录。
5. PR 描述说明变化、验证命令和结果、未执行项及必要迁移步骤。

生成器更改应在临时目录生成真实项目/Feature，而不是只测字符串和目录。AI 入口更新要检查技能正文、索引和文档链接一致。

修改 Skill 时遵循 [Skill 维护契约](.agents/skills/GOVERNANCE.md)。辅助命令与适用范围见 [工具清单](docs/tools.md)；目标端的证据口径见 [平台验收](docs/platform-acceptance.md)。

## 工具链与依赖

脚手架要求 Python 3.11 或更新版本，Flutter 版本由 `.fvmrc` 固定。依赖从 pubspec/lock 解析，代码生成组合一起升级。新 workspace 成员必须登记并提供测试；默认手写覆盖率门槛 80%。不要提交构建产物、生成的 Dart part 文件或本机绝对路径。

## Issue 与 PR

Bug 应给最小复现、输入命令、预期/实际结果和环境。模板/Skill 问题附 AI 实际读到的入口与生成结果，避免只描述“AI 不听话”。新能力说明适用场景、是否影响最小默认项目和可测试验收。

合并前确认公开接口、平台与例外已经记录。不要把尚未运行的平台或外部系统写成已验证。
