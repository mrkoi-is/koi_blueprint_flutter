# koi_api_bootstrap

可选认证/网络装配包，提供平台条件导入，避免 Native 网络实现进入 Web 编译。公开入口 [koi_api_bootstrap.dart](lib/koi_api_bootstrap.dart) 导出 bootstrapKoiApi、disposeKoiApi、createDefaultTokenSession，以及 bindings/options/runtime 和 token session 契约；这些契约不泄漏 Dio 或 koi_network 类型。

Native 初始化 koi_network，并可使用安全 token 存储；Web 的网络 runtime 是明确的空操作，token 仅在内存，刷新后需要重新登录。它不提供真实 Web API、主动 token 刷新或重启后的用户验证。应用 bootstrap 拥有设施并负责释放，provider 只消费注入依赖。

## 显式环境和具名后端

既有 `KoiApiBootstrapOptions(baseUrl: ..., environment: ...)` 保持单后端用法，默认 key 为 `main`。可以通过 `primaryBackendKey` 为主后端命名，并通过 `additionalBackends` 增加共享会话的服务：

```dart
const options = KoiApiBootstrapOptions(
  baseUrl: 'https://account.example.com/',
  environment: 'staging',
  primaryBackendKey: 'account',
  additionalBackends: [
    KoiBackendDefinition(
      key: 'reporting',
      purpose: '同一账号域的报表服务',
      baseUrl: 'https://reports.example.com/',
    ),
  ],
);
```

所有后端共用 `KoiApiBindings` 的可撤销 token session、响应解析器、编码器及日志/TLS/刷新白名单策略，不支持在同一 Runtime 内装配独立认证域或独立 adapter profile。每个 Native 后端都安装 token + revision 感知的 401 保护，旧请求不得撤销新会话。`runtime.backendKeys` 返回不可修改的名称集合。Web 仅保留这些声明并校验配置，仍不提供网络。

所有后端关闭自动重试，失败的 GET 和 POST 都只发送一次。需要重试的业务须先定义幂等和去重契约，再由相应拥有者实现策略。

401 会话白名单按规范化 URI 的 origin 和完整路径匹配。相对条目使用该后端的 Dio base URL/path 拼接规则，绝对 HTTP(S) 条目只允许对应 origin；查询参数或相似路径不会扩大白名单范围。真实 token refresh 仍未实现。

环境显式接受 `dev/development`、`test/testing`、`staging`、`prod/production`，不从构建模式推断；未知环境拒绝启动。所有 URL 必须为不含凭据、query、fragment 的绝对 HTTP(S) 地址，staging/production 要求 HTTPS 并强制证书验证。production 拒绝 `enableLogging` 和 `enableInternalLogging`，释放时复位全局 debug 开关。非法替换配置不会破坏活动 Runtime；并发 bootstrap 会被拒绝。

## Native 生成 Client 装配

仅平台适配层或 App bootstrap 导入 [koi_api_bootstrap_native.dart](lib/koi_api_bootstrap_native.dart)，使用 `buildKoiApiClient(runtime, 'account', (dio) => GeneratedClient(dio))` 构造并注入生成 Client。该显式 Native composition 入口接收 Dio factory，不由主入口重导出，不允许 presentation 或平台无关业务契约导入。

主后端名称映射到 koi_network 的 `main` module，`token` 保留给底层；附加后端不得占用 `main`、`token` 或与其他名称重复。释放或替换 Runtime 后，旧 factory 入口失效；调用方应先取消或等待在途请求，再释放 Runtime 及其 Client。释放旧 Runtime 不会破坏已替换的新 Runtime。

## 验证

根目录 bootstrap 后，本目录 `../../tool/flutterw test --no-pub`。行为测试覆盖配置边界、多后端会话与延迟 401、生产日志复位、生命周期、token 写入/退出串行化及持久化失败。源仓 validate 另外将 test/web_compile_smoke.dart 编译为 JS 并用 Node 运行，证明公共入口能在 Web 导入，不能据此声称真实 Web 请求通过。
