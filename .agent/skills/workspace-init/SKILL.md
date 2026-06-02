---
name: workspace-init
description: 初始化 Flutter workspace、Melos、根级工具链与 AI 资产
---

1. 确认根级 `pubspec.yaml` 使用 `workspace`
2. 确认 `apps/` 和 `packages/` 都被纳入 workspace
3. 确认 `analysis_options.yaml`、`Makefile`、`tool/dartw`、`tool/flutterw` 存在
4. 修改后优先跑：`pub get` → `generate` → `analyze` → `test`
