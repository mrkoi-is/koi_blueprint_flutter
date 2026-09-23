# Koi Flutter 架构说明

## 架构目标

- 面向长期演进的 Flutter Monorepo
- 对齐 Koi 系列项目的共享包沉淀方式
- 默认支持 AI 协作、代码生成、API 自动接入

## 技术决策

| 领域 | 选型 |
|---|---|
| Monorepo | Dart Workspace + Melos |
| 状态管理 | Riverpod 3 |
| 路由 | go_router |
| 代码生成 | build_runner |
| 数据模型 | Freezed + json_serializable |
| 错误处理 | fpdart + 统一 Failure |
| 网络 | koi_network |
| API 生成 | koi_swagger_parser |

SDK 按季度跟随 Flutter stable 升级，升级时同步 `.fvmrc`、根与成员 `pubspec.yaml` 的兼容范围、`.github/workflows/quality.yml` 的 Flutter 版本及校验、`pubspec.lock` 与版本文档。代码生成依赖按 README 中记录的兼容簇整体升级，不使用 `dependency_overrides` 跨越生成器声明的 analyzer 上限。
本地持久化刻意不内置：蓝图不预置 drift / hive / shared_preferences 等数据库或缓存依赖；有本地缓存或离线需求时按 Feature 引入，并在该 Feature 的 `data/` 层封装，不泄漏到 domain / presentation。

## 分层边界

### packages/koi_core
- 放失败类型、typedef、工具扩展
- 不放 UI、不放业务页面

### packages/koi_domain
- 放共享实体和值对象
- 尽量不耦合 Flutter

### packages/koi_ui
- 放主题、通用状态组件、基础按钮与布局壳子
- 不放业务 Feature Widget

### packages/koi_auth
- 放与业务用户类型解耦的认证状态模型
- 不直接绑定具体业务接口字段

### packages/koi_api_bootstrap
- 公共 API 放 token session、401、日志回调和平台无关 runtime
- Native 后端私下编排 `koi_network`；Web 后端明确 no-op，不导入 `dart:io`
- 为未来 `<project>_api` 和 `<project>_network` 预留接入点

### apps/<app>
- 只负责业务 Feature、App Router、第三方平台整合
- 稳定的跨 App 共享逻辑沉淀到 package；App 内复用先留在 shared

## Feature 规范

Feature 目录的标准骨架是三层：
- `data/`
- `domain/`
- `presentation/`

纯展示型、无数据与业务规则的 Feature（如 `splash`、`home` 壳页面）允许只保留 `presentation/` 层，不强行创建空目录。
默认不要把所有 Provider、Model、Screen 全堆在一个目录里。

## 路由规范

- `core/router/app_router.dart`：GoRouter 装配与 redirect
- `core/router/app_routes.dart`：类型化路由定义（`@TypedGoRoute` + go_router_builder）与路径常量
- `core/router/app_navigation.dart`：页面导航扩展，一律走生成的类型化路由（如 `const LoginRoute().go(context)`）
- 字符串路径常量仅供路由定义与 redirect 匹配，页面不直接用字符串路径跳转
- 页面不反向导入路由装配文件，避免 Router 与 Feature UI 循环依赖
- GoRouter 必须保持单实例，并通过 refresh listenable 响应认证状态

## 认证与环境规范

- Mock 认证只允许在 `dev` 环境启用
- Release 必须显式指定非 `dev` 环境，缺省或 `ENV=dev` 均拒绝启动
- staging / prod 未注入真实认证与 HTTPS API 时必须拒绝启动
- Token 持久化分平台：Native 默认经 `flutter_secure_storage`（Keychain / Keystore）安全存储，Web 回退内存会话，刷新后重新登录；不把认证凭据写入普通偏好存储
- 登录、登出与 401 必须共享同一个 token session
- 持久 token storage 只交给 `KoiApiBindings`；业务仓库与网络统一使用其公开的可撤销 session
- 401 必须同时匹配失败请求的 token 与 session revision，旧请求的延迟响应不得撤销新会话
- `koi_api_bootstrap` 只管理其 bootstrap runtime 的 main Dio；额外业务网络模块必须由自身网络包安装同等的 session-aware 401 处理

## API 接入规范

业务项目接 Swagger 时推荐：

```text
packages/<project>_api/      # 生成产物
packages/<project>_network/  # envelope / adapter / request executor
apps/<app>/                  # 业务消费层
```

这样做的好处是：
- 生成物和消费逻辑分离
- 网络错误、登录态、envelope 不污染页面层
- 后续可以直接跟 `koi_swagger_parser`、`koi_network` 对接
