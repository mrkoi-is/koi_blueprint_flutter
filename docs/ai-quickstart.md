# AI Quickstart

给 AI Agent 的最短上手路径。

## 最小读取顺序

1. `docs/ai-quickstart.md`
2. `AGENTS.md`
3. `.agent/skills/index.yaml`
4. 当前任务对应的 `SKILL.md`
5. 只有在需要时再读：
   - `docs/architecture/ARCHITECTURE.md`
   - `docs/architecture/MONOREPO_ARCHITECTURE.md`
   - `docs/architecture/PROJECT_STRUCTURE.md`

## 全局硬约束

- Monorepo：根级 `pubspec.yaml` 使用 `workspace`
- App 目录：`apps/<app_name>/lib/{core,features,shared}`
- 共享能力：统一放在 `packages/`
- 路由：默认 `go_router`
- 状态管理：默认 `Riverpod 3`
- 数据模型：默认 `Freezed + json_serializable`
- 网络：默认 `koi_network`

## 常见任务路由

- 初始化工作区：`workspace-init`
- 新增 Feature：`add-feature-module`
- 新增共享包：`add-shared-package`
- 接入 API 包：`add-generated-api-package`
- 调整路由：`add-routing`
- 架构审查：`architecture-review`
- 补测试：`testing-scaffold`

## 推荐执行顺序

1. 改源码
2. 运行 `format-check`
3. 运行 `generate-check`
4. 运行 `analyze`
5. 运行 `test`
6. 运行 `coverage`
