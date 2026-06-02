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
- 放认证状态模型与抽象
- 不直接绑定具体业务接口字段

### packages/koi_api_bootstrap
- 放 `koi_network` 初始化编排
- 为未来 `<project>_api` 和 `<project>_network` 预留接入点

### apps/<app>
- 只负责业务 Feature、App Router、第三方平台整合
- 所有共享逻辑优先沉淀到 package

## Feature 规范

每个 Feature 目录统一：
- `data/`
- `domain/`
- `presentation/`

默认不要把所有 Provider、Model、Screen 全堆在一个目录里。

## 路由规范

- `core/router/app_router.dart`：GoRouter 装配与 redirect
- `core/router/app_routes.dart`：路由定义
- 页面跳转优先使用类型安全路由

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
