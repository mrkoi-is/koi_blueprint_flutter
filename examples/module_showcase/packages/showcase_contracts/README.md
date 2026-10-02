# showcase_contracts

[模块宿主](../../README.md) 的示例共享能力，非所有 module 的强制依赖。公开入口 [showcase_contracts.dart](lib/showcase_contracts.dart) 导出纯 Dart ShowcaseRepository/ShowcaseServices 和 presentation 层的 activeShowcaseRepositoryProvider。

宿主 bootstrap 必须 override 当前会话 repository；未注入时明确抛出错误。repository 暴露 moduleId、generation、loadMessage，services 提供 refreshes 与事件记录。模块只消费契约，不导入宿主或其他模块实现。

根目录 bootstrap/generate-check 后，在本目录 `../../../../tool/flutterw test --no-pub`。测试覆盖缺失注入、能力替换和注入生命周期；共享服务的存活由宿主测试验证。
