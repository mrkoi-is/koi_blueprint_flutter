# Koi Flutter 蓝图 — Agent 入口

先读 [AI Quickstart](docs/ai-quickstart.md)，再从 [.agents/skills/index.yaml](.agents/skills/index.yaml) 选择当前任务的一个或少量技能。需要细节时才读其 references；不要全量加载技能。

## 架构契约

- 新项目使用 Dart Workspace + Melos；App 内按 `core / features / shared` 组织。
- `packages/` 放稳定共享能力；需要独立业务边界时使用 `modules/`。App/宿主负责装配，底层不得反向依赖 App，业务模块不互相导入实现。
- `domain` 是纯 Dart 契约与模型；`data` 是 IO/仓库实现；`application` 是用例、状态与编排；`presentation` 是 UI。`data` 与 `application` 可以共存，按职责建层。
- 新状态默认注解式 Riverpod 3。业务容器通过 provider 取数；展示组件可以接收不可变数据和回调。本地瞬态 UI 状态可以留在 Widget。
- 路由默认类型化 go_router；模型默认 Freezed/json_serializable。认证、网络、数据库按产品需求加入，最小新项目不继承演示登录。
- 架构权威入口：[ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md)。写 provider 前读 [状态管理规范](docs/architecture/state-management.md)；本地 IO/后台任务读 [桌面补充](docs/architecture/local-first-desktop.md)。

## 任务路由

| 任务 | Skill |
| --- | --- |
| 创建项目、初始化 workspace | `workspace-init` |
| 新增业务 Feature | `add-feature-module` |
| 编写页面与 provider | `state-management` |
| UI、主题、布局与交互 | 先读 [DESIGN.md](DESIGN.md)，按状态与测试职责选择 `state-management` / `testing-scaffold` |
| 新增共享 package | `add-shared-package` |
| 新增独立业务 module、切换会话 | `add-business-module` |
| 接入生成 API | `add-generated-api-package` |
| 新增或重构路由 | `add-routing` |
| 审查架构边界 | `architecture-review` |
| 补充测试 | `testing-scaffold` |

## 执行与验证

优先使用 `python3 blueprint.py --help` 和各子命令帮助，工具总览见 [工具清单](docs/tools.md)。Windows 使用 `py -3 blueprint.py`。完整门禁为 `python3 blueprint.py validate`：严格锁文件、生成、只读格式、架构/AI 资产、分析、成员测试、活动成员的 Chrome 浏览器测试、手写代码覆盖率（80%）。源仓库另执行 `templates` 继承资产检查；存在 API Web 冒烟入口时另执行 JS 编译及 Node 运行。无活动浏览器测试的项目不要求 Chrome。目标平台构建需单独报告，不能用其他平台构建代替。

先检查工作区变化，保留用户已有修改。交付说明区分“修改完成”“本地验证通过”“目标平台验证”“未执行项”。不要把样例、规划或说明文档写成已完成的真实业务能力。

## AI 资产单一来源

正文只维护 `.agents/skills/`。`CLAUDE.md` 与 `.cursor/rules/` 只指向入口。发现不等于已执行；不支持自动发现的工具直接按路径读取。见 [发现机制](docs/agent-skill-rule-discovery.md)。
