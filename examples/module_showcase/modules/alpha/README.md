# Showcase Alpha

[模块宿主](../../README.md) 的独立业务 package。公开入口 [showcase_alpha.dart](lib/showcase_alpha.dart) 导出 createAlphaModule、AlphaRoute 与 AlphaDetailsRoute；模块 ID 为 alpha。调用方传入 ShowcaseServices，session factory 创建当前会话 repository。

路由声明、data、provider 与页面位于 src，宿主只依赖公开入口；不导入 Beta 或宿主实现。会话拥有 refresh 订阅和延时工作，关闭时取消；共享 services 仍由宿主持有。

根目录 bootstrap/generate-check 后，本目录 `../../../../tool/flutterw test --no-pub`。测试覆盖公开类型化入口、延时取消、session 关闭与错误呈现；跨模块路由与旧结果拒绝见宿主测试。本模块不是 blueprint module 的生成源，最小生成源为 minimal_module。
