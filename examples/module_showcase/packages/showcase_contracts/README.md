# showcase_contracts

[模块宿主](../../README.md) 的示例共享能力，非所有 module 的强制依赖。公开入口 [showcase_contracts.dart](lib/showcase_contracts.dart) 只导出纯 Dart ShowcaseRepository/ShowcaseServices，不提供 provider。

每个模块在自己的 `presentation/providers` 声明 `showcaseRepositoryProvider`。宿主 bootstrap 分别 override Alpha 与 Beta；未注入时明确抛出错误。repository 暴露 moduleId、generation、loadMessage，services 提供 refreshes 与事件记录。模块只消费契约，不导入宿主或其他模块实现。

根目录 bootstrap/generate-check 后，在本目录 `../../../../tool/flutterw test --no-pub`。本包只验证契约类型。缺失注入、能力替换和注入生命周期由模块测试与宿主测试覆盖。
