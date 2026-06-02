# 其他 AI 工具如何接入本仓库

## Claude Code / Codex / Cursor

- 先读取根级 `AGENTS.md`
- 再根据任务读取 `.agent/skills/index.yaml`
- 只加载需要的少数 Skill

## 如果工具不支持自动发现

手动按下面顺序：

1. `docs/ai-quickstart.md`
2. `AGENTS.md`
3. `.agent/skills/index.yaml`
4. 对应 Skill 的 `SKILL.md`
