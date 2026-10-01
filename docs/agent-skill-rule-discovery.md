# AI 入口与技能发现

## 单一正文

`.agent/skills/<id>/SKILL.md` 是唯一技能正文，`index.yaml` 维护任务索引。`.agents/skills/<id>/SKILL.md` 仅保留相同 name/description 和指向正文的读取指令，使用普通文件便于 Windows checkout。禁止在适配文件另写架构规范。

| 客户端 | 接入入口 | 验证方式 |
| --- | --- | --- |
| Codex | AGENTS.md + 原生 `.agents/skills/` 适配 | 检查技能是否被发现，再以具体任务确认读到 canonical 文件 |
| Claude Code | CLAUDE.md 导入 AGENTS.md；按索引读 canonical | 在客户端确认项目指令已加载；AGENTS 支持依客户端版本/配置而定 |
| Cursor | `.cursor/rules/koi-workspace.mdc` 路由到 AGENTS/索引 | 检查 project rules 生效，再确认相关 Skill 被读取 |
| 其他工具 | 手动指定 AGENTS、AI Quickstart、索引与相关 Skill | 让工具复述任务对应的约束和执行入口，再做最小任务 |

客户端发现机制会变化；本仓库不承诺所有工具自动加载自定义目录。即使识别了 Skill，也仍须通过生成与行为测试证明执行正确。官方资料见 [设计参考](architecture/references.md)。

## 修改与同步

修改 canonical 后同步 adapter 的 frontmatter；正文适配固定为“读取 canonical + 只维护 canonical”的两句英文。索引 id、目录名、frontmatter name 与 adapter 一一对应。新增/删除 Skill 时同改索引和适配入口；校验路径、示例地图、references 和跨平台可读性。

技术事实只在架构文档维护，执行步骤只在 Skill 维护，完整示例只在受测源码维护。避免把完整架构复制到 AGENTS、CLAUDE 和 Cursor 三处。
