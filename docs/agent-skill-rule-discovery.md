# Agent / Skill / Rule 发现机制

本仓库的 AI 资产遵循以下优先顺序：

1. 根级 `AGENTS.md`
2. `.agent/skills/index.yaml`
3. `.agent/skills/<skill-id>/SKILL.md`
4. `.cursor/rules/*.mdc`

## 设计原则

- `AGENTS.md` 负责全局入口与约束
- `index.yaml` 负责意图到 Skill 的路由
- `SKILL.md` 负责具体执行步骤
- `.cursor/rules/` 只做轻量提示，不复制 Skill 正文
