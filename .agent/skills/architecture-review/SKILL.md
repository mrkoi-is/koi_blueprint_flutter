---
name: architecture-review
description: 对照蓝图审查 Flutter workspace 的结构、边界与可维护性
---

重点检查：
- 是否仍是 `workspace + melos` 结构
- App 是否按 `core/features/shared` 分层
- 共享逻辑是否沉淀到 `packages/`
- API 生成物是否与消费层分离
- 是否具备只读格式、代码生成、`analyze / test / coverage` 自动门禁
- App 是否至少有一个可实际构建的平台目录
