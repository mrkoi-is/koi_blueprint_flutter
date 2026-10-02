# koi_api_bootstrap

可选认证/网络装配包，提供平台条件导入，避免 Native 网络实现进入 Web 编译。公开入口 [koi_api_bootstrap.dart](lib/koi_api_bootstrap.dart) 导出 bootstrapKoiApi、disposeKoiApi、createDefaultTokenSession，以及 bindings/options/runtime 和 token session 契约。

Native 初始化 koi_network，并可使用安全 token 存储；Web 的网络 runtime 是明确的空操作，token 仅在内存，刷新后需要重新登录。它不提供真实 Web API、主动 token 刷新或重启后的用户验证。应用 bootstrap 拥有设施并负责释放，provider 只消费注入依赖。

根目录 bootstrap 后，本目录 `../../tool/flutterw test --no-pub`。测试覆盖绑定、重复释放、token 写入/退出串行化、持久化失败。源仓 validate 另外将 test/web_compile_smoke.dart 编译为 JS 并用 Node 运行，证明公共入口能在 Web 导入，不能据此声称真实 Web 请求通过。
