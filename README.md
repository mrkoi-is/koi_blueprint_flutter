# Koi Blueprint Flutter

面向 Koi 系列项目的 Flutter Monorepo 蓝图。

这个蓝图直接对齐你当前更偏好的技术路线：
- `jiejing`：作为技术栈基线，采用 `workspace + melos + Riverpod 3 + go_router + Freezed + koi_network`
- `learning_officer_oa`：作为目录组织参考，保留 `common / routes / legacy 迁移思路` 的可借鉴经验，但不继续使用 GetX

## 核心目标

- 新项目默认就是 Monorepo，而不是后期再拆
- App 代码按 `core / features / shared` 分层组织
- 共享能力下沉到 `packages/`，避免业务 App 之间互相依赖
- API 集成默认预留 `koi_swagger_parser + koi_network` 接口位
- AI 工具默认可用，仓库打开即可从 `AGENTS.md` → `.agent/skills/` 路由

## 当前蓝图内容

```text
koi_blueprint_flutter/
├── apps/
│   └── koi_admin_app/          # 可运行示例 App
├── packages/
│   ├── koi_core/               # 失败类型、typedef、扩展
│   ├── koi_domain/             # 共享领域实体
│   ├── koi_ui/                 # 主题与通用状态组件
│   ├── koi_auth/               # 认证状态模型
│   └── koi_api_bootstrap/      # koi_network 初始化入口
├── docs/
│   └── architecture/
├── .agent/skills/
├── .cursor/rules/
├── tool/
│   ├── dartw                   # Dart 包装器
│   └── flutterw                # Flutter 包装器
└── scripts/
```

## 技术栈基线

- Flutter Workspace (`pubspec.yaml` 顶层 `workspace`)
- Melos 7
- Riverpod 3 + `riverpod_generator`
- go_router 17 + `go_router_builder`
- Freezed 3 + `json_serializable`
- `fpdart`
- `koi_network`

## 快速开始

如果你的 `flutter` 不在 PATH，请先指定：

```bash
export FLUTTER_BIN=/path/to/flutter
export DART_BIN=/path/to/dart
```

然后执行：

```bash
make bootstrap
make generate
make analyze
make test
```

或直接使用 Melos：

```bash
export PATH="$PWD/tool:$PATH"
./tool/dartw pub get
./tool/dartw run melos bootstrap
./tool/dartw run melos run generate --no-select
./tool/dartw run melos run analyze --no-select
./tool/dartw run melos run test --no-select
```

## API 包接入约定

未来业务项目推荐额外创建：

```text
packages/<project>_api/
packages/<project>_network/
```

其中：
- `<project>_api` 由 `koi_swagger_parser` 生成
- `<project>_network` 负责编排 `koi_network` 的 adapter、错误处理、登录态刷新、envelope 解析
- App 层不直接散落处理 Dio 细节

## 为什么这样设计

- 比单 App 仓库更适合 Koi 系列多端复用
- 比旧 GetX 项目更利于长期维护、测试与 AI 协作
- 比“业务都堆在 app/lib 里”更容易沉淀共享包和行业方案

详细说明见：
- `docs/ai-quickstart.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/MONOREPO_ARCHITECTURE.md`
- `docs/architecture/PROJECT_STRUCTURE.md`
