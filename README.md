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
│   └── koi_api_bootstrap/      # Native 网络编排 + Web 安全降级
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
- Flutter 3.41.2 / Dart 3.11（见 `.fvmrc`）
- Melos 7.8
- Riverpod 3 + `riverpod_generator`
- go_router 17 + `go_router_builder`
- Freezed 3 + `json_serializable`
- `fpdart`
- `koi_network`

## SDK 升级策略

本蓝图按季度跟随 Flutter stable 升级。每次升级必须同步三处：
- `.fvmrc` 中的 Flutter 版本
- `.github/workflows/quality.yml` 中的 `flutter-version` 及其 grep 校验步骤
- `CHANGELOG.md` 中记录本次升级

## 快速开始

如果你的 `flutter` 不在 PATH，请先指定：

```bash
export FLUTTER_BIN=/path/to/flutter
export DART_BIN=/path/to/dart
```

然后执行：

```bash
make bootstrap
make format-check
make generate-check
make analyze
make test
make coverage
```

或直接使用 Melos：

```bash
export PATH="$PWD/tool:$PATH"
./tool/dartw pub get
./tool/melos bootstrap
./tool/melos run format:check --no-select
./scripts/check_generated.sh
./tool/melos run analyze --no-select
./tool/melos run test --no-select
./scripts/check_coverage.sh
```

运行 Web 示例：

```bash
cd apps/koi_admin_app
../../tool/flutterw run -d chrome
```

Debug/Profile 未指定环境时默认 `ENV=dev`，使用 Mock 登录；Native 令牌经安全存储
（Keychain / Keystore）持久化，Web 令牌只保存在内存中，刷新后需重新登录。
Release 必须显式传入 `--dart-define=ENV=staging` 或 `prod`，并禁止 `dev` Mock 认证。
`staging` / `prod` 不会回退到 Mock，并会在真实 API 或认证数据源未配置时拒绝启动。

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

`koi_api_bootstrap` 的公共 API 不暴露 Dio 或 `koi_network` 类型。Native
运行时注入 token、401 和日志回调；Web 示例使用明确的 no-op 网络 runtime，
因此可以构建和运行，但真实 Web API 接入需要提供项目自己的 Web 网络实现。
该 bootstrap 只管理自己的 main runtime；额外业务网络模块应在各自的 network package 中复用同等的 token/revision 401 保护。

## 质量门禁

- GitHub Actions 固定 Flutter 版本并执行格式、代码生成、分析、测试、覆盖率和 Web 构建
- 6 个 Workspace 成员都必须提供测试
- 手写代码合并行覆盖率不得低于 60%
- 含可执行逻辑的新源码必须进入覆盖率报告，平台/入口文件由 Web 构建门禁补充验证
- 生成物（`*.g.dart` / `*.freezed.dart`）不入库，本地与 CI 通过 `generate` 重新生成
- 当前蓝图测试覆盖认证成功/失败、路由重定向、401、序列化和共享 UI

## 为什么这样设计

- 比单 App 仓库更适合 Koi 系列多端复用
- 比旧 GetX 项目更利于长期维护、测试与 AI 协作
- 比“业务都堆在 app/lib 里”更容易沉淀共享包和行业方案

详细说明见：
- `docs/ai-quickstart.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/MONOREPO_ARCHITECTURE.md`
- `docs/architecture/PROJECT_STRUCTURE.md`
