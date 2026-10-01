# Minimal Module

生成器的最小业务 module 模板。公开入口为 `lib/minimal_module.dart`，导出 `createMinimalModule()` 和类型化 `MinimalModuleRoute`。它只需要 Flutter、go_router、koi_modules，不包含登录、网络、共享业务契约或后台服务。

宿主将 descriptor 放入 `KoiModuleCatalog<Object>`，组合 `catalog.routes` 和导航，再根据自身会话需求创建 `KoiModuleRuntime<Object>`。出现实际共享业务能力时才添加契约 package，并将泛型 `Object` 改成该公开接口。

本模块自身是 package，不拥有 App 平台 runner、共享基础设施或宿主 router。
