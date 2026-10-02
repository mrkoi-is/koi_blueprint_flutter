# Koi Blueprint Flutter

面向新项目和 AI 协作的 Flutter Monorepo 蓝图：用可运行样例、任务技能、脚手架与质量门禁，让实现遵循同一套架构。

默认技术路线为 Dart Workspace + Melos、Riverpod 3、类型化 go_router、Freezed/json_serializable。所有新项目默认使用 koi_ui 的统一主题；minimal 保持最小业务，workbench 是文本资料、图片/视频素材与任务的可选模板。默认包含本地化、错误接线与来源信息；诊断持久化、网络、数据库、图片、平台集成及独立业务模块按需求加入。

## 创建项目

准备 Python 3.11 或更新版本，以及与 `.fvmrc` 匹配的 Flutter SDK。从蓝图根目录执行：

```sh
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web --dry-run
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web
python3 blueprint.py create studio --output ../studio --org com.example --template workbench --platforms web,macos
cd ../field_notes
python3 blueprint.py doctor --purpose run
python3 blueprint.py devices
python3 blueprint.py run --app apps/field_notes_app --device chrome
# 退出运行后验证：
python3 blueprint.py doctor --purpose validate
python3 blueprint.py validate
python3 blueprint.py build --app apps/field_notes_app --platforms web
```

生成工程不复制源仓库的本地 SDK。进入新工程后可执行 `fvm install`、`fvm use 3.47.2`，或将 `FLUTTER_BIN` 指向已有的固定版本 Flutter 可执行文件。启动、设备列表、构建与验证均使用同一 SDK 选择规则。

Windows 使用 `py -3 blueprint.py`。平台可选 `web,android,ios,macos,windows,linux`；对应平台的构建需要合适主机和 SDK。`--dry-run` 用于检查计划，生成成功不代表所有平台都构建通过。完整说明见 [创建项目](docs/new-project.md)。

## 日常开发

```sh
python3 blueprint.py feature apps/field_notes_app welcome --kind presentation
python3 blueprint.py feature apps/field_notes_app catalog --kind api
python3 blueprint.py feature apps/field_notes_app drafts --kind local
python3 blueprint.py module reporting --workspace .
python3 blueprint.py validate
```

脚手架之后完成真实业务字段、宿主导航、依赖注入和行为测试。根 pubspec 是 workspace 成员的唯一来源；`blueprint.json` schema 2 记录项目身份、来源、配置、能力与受管文件基线。

配置驱动创建支持两种模板和按需能力。将自己的 schema 1 JSON 交给 `create --config`；完整可复制配置及字段限制见 [创建项目](docs/new-project.md)。例如：

```sh
# 从源蓝图创建；配置中包含 org/platforms/capabilities/buildProfiles。
python3 blueprint.py create notes --output ../notes --config blueprint.local.json
cd ../notes
python3 blueprint.py capability list --app apps/notes_app
python3 blueprint.py capability add images --app apps/notes_app --dry-run
python3 blueprint.py capability add images --app apps/notes_app
python3 blueprint.py build --app apps/notes_app --profile web-local
python3 blueprint.py package --app apps/notes_app --profile web-local
python3 blueprint.py upgrade-report --app apps/notes_app --source ../koi_blueprint_flutter
```

images 自动安装 network；安装只采用内置配方，依赖、原生配置、测试和清单一起装配。重复安装检查文件所有权，用户修改或版本冲突会拒绝覆盖。升级报告仅比较基线/本地/上游并输出迁移说明，不自动修改下游。旧 schema 1 工程先人工迁移装配与基线，不能直接增装能力。

profile 明确平台、架构、模式、channel 和格式；构建与打包清单绑定实际产物和输入摘要，过期或修改过的产物不能直接打包。doctor 显示工具版本、已装能力依赖和实际动态库加载/资产校验结果；六端设备运行、安装及系统交互仍单独验收，未执行项标记 NOT_RUN。

## AI 从哪里开始

读取 [AGENTS.md](AGENTS.md) → [AI Quickstart](docs/ai-quickstart.md) → [技能索引](.agents/skills/index.yaml)，按任务加载 9 个技能中的少数。技能正文只维护在 `.agents/skills/`。客户端差异与手动接入见 [发现机制](docs/agent-skill-rule-discovery.md)。

## 架构与样例

```text
apps/       宿主、bootstrap、router、core/features/shared
modules/    有独立边界的业务模块（按需）
packages/   稳定共享能力与契约
examples/   最小宿主、三类 Feature、模块宿主
.agents/    技能正文、索引与原生发现入口
```

Feature 按职责选择 domain/data/application/presentation；data 与 application 可以共存。业务容器通过 provider 订阅，展示组件可以使用不可变参数和回调。状态拥有者、自动销毁、异步错误和过期结果是架构的一部分。

- [Flutter 设计规范](DESIGN.md)
- [桌面设计对照与依据](docs/research/desktop-ui-design-comparison-2026-09-30.md)
- [架构契约](docs/architecture/ARCHITECTURE.md)
- [状态与生命周期](docs/architecture/state-management.md)
- [模块契约](docs/architecture/modules.md)
- [本地优先与桌面](docs/architecture/local-first-desktop.md)
- [受测样例地图](docs/examples.md)
- [设计参考与取舍](docs/architecture/references.md)

认证样例展示 bootstrap、token session、401 隔离与路由；Native 可持久化 token，Web 为内存会话。示例没有跨进程用户会话恢复、真实刷新 token 或真实 Web API。staging/prod 未注入真实认证/API 时拒绝启动。这些行为属于认证示例，不进入默认最小项目。

## 工具链与验证

当前基线：Flutter 3.47.2 / Dart 3.13.2、Melos 8.9、Riverpod 3.4.3，实际版本以 `.fvmrc`、pubspec 和 lock 为准。SDK 升级同时更新 CI、环境约束、锁文件、生成器兼容组合与版本文档；不要用 dependency_overrides 强行跨越生成器约束。

SDK 选择顺序是 `FLUTTER_BIN` → 项目 `.fvm/flutter_sdk` → PATH 中的 Flutter；Python 入口从所选 Flutter SDK 同目录定位 Dart，使用同一 SDK 运行生成与测试。锁文件使用 pub.dev，严格锁文件检查应使用同一包源。

`python3 blueprint.py validate` 是统一入口。源仓库完整验证需要 Chrome 和 Node；生成项目只在活动成员存在浏览器测试时要求 Chrome，只在存在 API Web 冒烟入口时要求 Node。默认 minimal 两者都不要求；workbench 要求 Chrome。`doctor --purpose validate` 会提前检查这些条件。源仓库 validate 还检查两个模板的真实继承资产；完整递归验收另运行 `python3 tool/generator_smoke.py`。质量要求包括 AI 资产/引用、架构边界、代码生成、只读格式、fatal-infos 分析、成员测试和 **80% 手写代码覆盖率**。生成的 Dart part 文件不入库。目标平台使用 `build` 单独验证；测试与本地构建不能替代真实业务后端或设备验收。

已有 `make validate` 与 shell 入口保留为兼容包装。完整命令见 [工具清单](docs/tools.md) 和 [Melos 使用](MELOS_USAGE.md)。详见 [测试策略](docs/test_strategy.md) 与 [平台验收](docs/platform-acceptance.md)。仓库中的配置和测试描述验收要求，当前是否通过以本次执行结果为准。当前结果与平台缺口见 [验收索引](docs/validation/README.md)；[2026-09-29 记录](docs/validation/2026-09-29.md)保留为历史证据。

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。修改公共接口、架构或生成器时，一起更新样例、Skill、文档和行为测试；Issue/PR 应给出可复现输入与实际验证结果。
