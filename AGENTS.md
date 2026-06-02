# Koi Flutter 蓝图 — Agent 说明

本文件供 Codex、Claude Code、Cursor、Antigravity 等工具在仓库根目录自动加载。

## 必读

- AI 最短入口：`docs/ai-quickstart.md`
- 架构权威说明：`docs/architecture/ARCHITECTURE.md`
- Monorepo 设计：`docs/architecture/MONOREPO_ARCHITECTURE.md`
- 目录与迁移策略：`docs/architecture/PROJECT_STRUCTURE.md`

## 技术栈基线

- Flutter Workspace + Melos 7
- Riverpod 3 + `riverpod_generator`
- go_router + `go_router_builder`
- Freezed + `json_serializable`
- `koi_network`
- Feature-first：`core / features / shared / packages`

## Agent Skills（单一事实源）

- 位置：`.agent/skills/<skill-id>/SKILL.md`
- 索引：`.agent/skills/index.yaml`
- Cursor 提示：`.cursor/rules/`

### Skill 索引（任务 → 目录）

| 用户意图 | Skill |
|---|---|
| 新建 workspace / 初始化项目 | `workspace-init` |
| 新增业务 Feature | `add-feature-module` |
| 新增共享 package | `add-shared-package` |
| 接入 Swagger 生成 API 包 | `add-generated-api-package` |
| 新增或重构路由 | `add-routing` |
| 架构审查 | `architecture-review` |
| 补测试 | `testing-scaffold` |

## 默认执行顺序

1. 先读 `docs/ai-quickstart.md`
2. 再读 `AGENTS.md`
3. 再读 `.agent/skills/index.yaml`
4. 只加载当前任务对应的少数 Skill
5. 最后跑 `generate / analyze / test`
