# Koi Flutter 架构契约

本文件定义新项目的默认架构。维护存量项目时，先核对有效决策、已有测试和局部实现；例外必须写明原因、边界和验证，不能由某次偶然实现推导出通用规则。

## 不变量与默认选型

| 类别 | 约定 |
| --- | --- |
| 不变量 | 单向依赖、明确状态拥有者、可替换的数据边界、可测试业务逻辑、可追溯生成流程 |
| 工程默认 | Dart Workspace + Melos；App 按 core/features/shared 组织 |
| 状态默认 | Riverpod 3 + riverpod_generator；生命周期和错误语义见 [状态规范](state-management.md) |
| 路由默认 | go_router + go_router_builder；宿主统一装配 |
| 模型默认 | Freezed + json_serializable；兼容既有序列化格式时可保留有测试的手写实现 |
| 按需能力 | 认证、koi_network、Swagger、数据库、原生平台服务 |
| UI 默认 | koi_ui + Material 3；语义 token、density 和自适应规范见 [UI 契约](ui-and-adaptive.md) |

版本以 `.fvmrc`、各 pubspec 和根锁文件为事实来源。SDK 升级同时更新 CI 和生成器兼容组合，不用 dependency_overrides 掩盖生成器冲突。

## 目录与依赖

```text
apps/<app>/lib/
  core/          # bootstrap、router、平台适配、应用配置
  features/<feature>/
    domain/      # 纯 Dart 实体、值对象、端口/仓库接口
    data/        # API、文件、数据库等 IO 与仓库实现（按需）
    application/ # 用例、命令、状态与编排（按需）
    presentation/# 页面、组件、provider 与展示模型
  shared/        # 当前 App 内稳定复用
  shell/         # 可选。组合 feature 页面；coordinators 只依赖 domain 或 application
packages/<name>/ # 跨 App 稳定共享能力。Feature 在 lib/src/features
```

仓库根没有 `modules/`。需要会话边界时，模块样例放在 `examples/module_showcase/modules/{alpha,beta}` 和 `examples/minimal_module`，源码使用 `lib/src/features`。

- `data` 实现 domain 端口，`application` 消费端口；二者可以共存。只有实际职责存在时才建层。
- `shell/` 可以组合 feature 页面。`shell/coordinators/` 不导入 presentation。
- `presentation` 消费 application/provider 与模型，不直接执行 HTTP、SQL、文件 IO 或创建基础设施。
- Feature provider 统一放 `presentation/providers/`；全局装配 provider 放 `core/providers/`。`application/` 保留业务编排，不建立另一套 provider。
- domain 不依赖 Flutter、IO 或 presentation；页面特有展示模型放 `presentation/models/`，业务用例与编排放 application。
- 纯展示 Feature 可以只有 presentation。跨 App 的共享实体才进入 可选的 `koi_domain` 包；App 私有实体留在 Feature。
- App 之间不互相导入；package 不反向导入 App；业务 module 通过公共契约协作，不直接导入其他 module 实现。

详细约定见 [项目结构](PROJECT_STRUCTURE.md)、[Monorepo](MONOREPO_ARCHITECTURE.md)、[本地优先](local-first-desktop.md)。

## 装配与模块

App 的 bootstrap 创建基础设施并通过 provider override 注入。创建资源的一方负责释放，借用资源的一方只解除自己的订阅。独立模块由 `koi_modules` 契约和宿主组合；模块切换要取消/隔离旧会话结果并释放会话资源，共享服务仍由宿主拥有。见 [模块契约](modules.md)。

API/local Feature 的 `<feature>.dart` 是业务入口，导出模型、端口和页面；`<feature>_composition.dart` 是宿主装配入口，导出实现与注入声明。两者按消费目的读取，不要求每个 Feature 一个 contracts 包。独立 module 的宿主仍只消费模块根入口，由该入口选择导出公开装配与业务能力。

## 常见对象的职责

| 对象 | 负责什么 |
| --- | --- |
| Controller/Notifier | 一组查询/分页/提交及其展示状态，取消或拒绝过期结果 |
| Session | 有明确生命周期的业务状态与命令；拥有 revision、任务和取消登记 |
| Repository | 数据端口及持久化/远程读取实现，保存格式和冲突语义 |
| Workflow | Session 内一个可理解的 IO 流程或队列，通过内部接口更新最新状态 |

注释说明拥有者、关闭顺序与行为不变量。根据真实职责拆分，不以类名或文件行数机械增加 UseCase/抽象层。纯展示、API 查询提交、长期本地任务的具体阅读路线见 [样例地图](../examples.md)。

## 路由

`core/router/app_routes.dart` 声明类型化路由；`app_router.dart` 创建并释放 GoRouter；`app_navigation.dart` 可提供面向页面的导航入口。业务页面不导入 router 装配文件。保持 router 身份稳定，使用刷新通知响应登录态；不因每次状态变化重建整个 router。

## 网络与认证示例的适用范围

[认证样例](../examples.md) 演示认证：dev 可使用 Mock；staging/prod 缺少真实认证/API 时拒绝启动。登录、登出与 401 共享可撤销 token session；延迟 401 通过 token + revision 隔离。Native 持久化 token，Web 使用内存会话。示例没有跨进程用户会话恢复，也没有真实 token refresh。

`koi_api_bootstrap` 公共 API 不泄漏 Dio 或 koi_network 类型；Web 后端为 no-op，真实 Web API 需自己的实现。Native 多 Host 共用同一组 bindings 和安全/会话策略，每个后端安装 session-aware 401 保护；生成 Client 通过独立 Native 装配入口取得受管传输。独立认证域或不兼容协议需隔离的 Transport。以上属于认证/API 场景，不强加到最小项目或离线工具。

生成 API 置于 `<project>_api`，消费适配置于 `<project>_network`；生成源码不手工补丁，修改输入或生成器。联网项目登记实际出口，OpenAPI 输入、配置和输出通过 provenance 追溯。装配、环境/TLS、日志、生成及静态门禁的详细边界见 [网络标准](NETWORK_ARCHITECTURE_STANDARD.md)。

## 维护契约

架构改动同步相关 Skill、样例、脚手架与测试。文档写清默认选择和条件例外；验证记录写明实际执行命令及平台。设计参考和个人项目经验见 [参考依据](references.md)。分阶段收口口径、目录和产品例外见 [治理方案](governance.md)。下游使用不依赖这些原始仓库。
