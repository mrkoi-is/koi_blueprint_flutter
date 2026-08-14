---
name: add-routing
description: 调整 go_router 路由与 redirect 逻辑
---

1. 路由定义与路径常量集中在 `core/router/app_routes.dart`（`@TypedGoRoute` + go_router_builder 生成）
2. GoRouter 装配与 redirect 集中在 `core/router/app_router.dart`
3. 页面导航一律走类型化路由扩展（如 `const LoginRoute().go(context)`），字符串路径常量仅供路由定义与 redirect 匹配
4. 路由变更后补至少一条冒烟测试或页面测试
5. 避免页面内部硬编码字符串路径
