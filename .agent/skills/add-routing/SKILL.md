---
name: add-routing
description: 调整 go_router 路由与 redirect 逻辑
---

1. 路由定义集中在 `core/router/app_routes.dart`
2. GoRouter 装配与 redirect 集中在 `core/router/app_router.dart`
3. 路由变更后补至少一条冒烟测试或页面测试
4. 避免页面内部硬编码字符串路径
