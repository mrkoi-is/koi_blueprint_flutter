---
name: add-routing
description: 新增类型化 go_router 路由并验证宿主注册、重定向、参数和路由生命周期。
---

## 目标
让新增页面可达且导航参数类型明确，保持宿主 router 生命周期稳定。

## 决策
区分独立页面、壳内导航项、弹窗和业务 module。普通 Widget 不需要都创建路由；module 路由由宿主组合。

## 流程
1. 在 `core/router/app_routes.dart` 定义 TypedGoRoute 或使用模块公开路由贡献。
2. 在 `app_router.dart` 完成唯一装配；页面通过类型化扩展或 `app_navigation.dart` 导航。
3. 定义路径/查询参数缺失与无效值行为；传输数据不要依赖不可恢复的任意 extra。
4. 认证重定向通过 refresh 机制响应状态，不在 provider 每次变化时创建新 GoRouter。
5. 运行生成，补可达性、参数解析、redirect 和 dispose 测试。

## 核心规则
- 页面不导入 router 装配文件，避免 UI 与 router 循环依赖。
- 路径常量用于定义/匹配；导航默认用生成的类型化扩展。
- 独立展示组件可接收 onTap 等回调，不必依赖 router。
- 没有认证需求时不复制示例登录 redirect。

## 验证
参照 [认证路由样例](../../../docs/examples.md) 和 [模块宿主样例](../../../docs/examples.md)。生成通过不等于所有导航入口已可达，至少执行一条宿主到新页面的测试。
