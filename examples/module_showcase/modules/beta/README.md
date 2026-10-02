# Showcase Beta

[模块宿主](../../README.md) 的独立业务 package。公开入口 [showcase_beta.dart](lib/showcase_beta.dart) 导出 createBetaModule、BetaRoute 与 BetaDetailsRoute；模块 ID 为 beta。宿主注入 ShowcaseServices，并用 session factory 持有 repository。

不导入 Alpha 或宿主实现。session 负责 refresh 订阅与可取消延时工作；关闭后不能提交迟到结果。宿主的稳定 router 支持 /beta/details 含 query/fragment 的冷启动，该组合行为在宿主测试中验证。

根目录 bootstrap/generate-check 后，本目录 `../../../../tool/flutterw test --no-pub`。测试覆盖取消、关闭、公开路由和错误呈现；跨模块导航见宿主测试。最小 module 生成源为 minimal_module，本包用于完整组合示例。
