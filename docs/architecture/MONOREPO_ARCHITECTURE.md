# Koi Flutter Monorepo 架构

> 基线来源：`jiejing` 的技术栈选择 + `learning_officer_oa` 对目录组织和历史迁移的经验

## 顶层结构

```text
koi_blueprint_flutter/
├── apps/
├── packages/
├── docs/
├── legacy/
├── scripts/
├── tool/
└── pubspec.yaml
```

## 依赖规则

- App 可以依赖任意 `packages/*`
- Package 只能依赖更底层 package
- Package 不允许反向依赖 App
- App 之间不直接依赖
- 公共 Package API 不向 App 泄漏 Dio 等底层实现类型

## 推荐包分层

```text
apps/<app>
  ├── koi_ui
  ├── koi_domain
  ├── koi_core
  └── koi_api_bootstrap / <project>_api / <project>_network

koi_auth  # 独立包：与上述分层平级，不依赖 koi_core 等任何分层内 package
```

`koi_auth` 刻意保持独立：不依赖 `koi_core`，只依赖 `freezed_annotation`，
让认证状态模型自包含、可被任意端独立复用，不被分层规则强制挂载。

## 适合 Koi 的原因

- 可以把 `koi_network`、`koi_swagger_parser`、未来 `koi_blueprint_flutter` 的能力串起来
- 共享 UI、共享领域对象、共享认证模型可以自然沉淀到 package
- 后续接新端时，不需要再拆仓库或大规模搬代码
- 平台专属实现通过条件导入隔离，Web 编译不遍历 Native `dart:io` 代码
