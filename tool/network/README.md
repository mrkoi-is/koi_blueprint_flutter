# 网络出口与迁移门禁

`egress_manifest.json` 登记当前已识别的联网能力，`python3 blueprint.py check network`
执行静态基础 lint 和清单回归测试。它不代替运行时出口观测、真实会话行为或发布验收。

`scripts/test/validate_network_architecture_test.dart` 实际加载 Draft 2020-12
JSON Schema，并用本地正反例同时回归 schema 与 Dart validator。黑盒进程使用
`DART_BIN` 或当前 Flutter SDK 内的 Dart，不使用 `flutter_tester` 执行 CLI。

该能力按需启用：完整验证只在存在清单时运行网络检查。离线项目可不接入，已接入的
离线项目可以使用 `entries: []`；静态检查仍会拒绝代码中未声明的 HTTP(S) origin。

## 扫描范围与构造边界

Dart 边界、字面量 HTTP(S) origin 和原生 TLS 模式扫描 `apps/`、`packages/`、
`modules/`、`examples/`，跳过 build、SDK 缓存和原生依赖产物。它是源码模式 lint，
不能追踪任意字符串拼接、重定向、插件内部 Host 或运行时 URL，也不证明所有协议均已发现。

`bootstrap.dart`、`core/network/` 可以创建 Dio。既有 transport 实现可通过
`boundaries.transportConstructionPaths` 登记**存在的精确 Dart 文件路径**；目录、glob
和不存在的路径会失败。该登记只允许在指定文件构造 Dio，不能跳过 presentation、
origin 或 TLS 检查。主线 Network Lab 的 Native transport 使用此边界。

## 仓库样例清单

当前清单覆盖认证样例的 Native API 基础设施，以及 Network Lab HTTP、下载、远程图片，
Device Lab WebSocket 配对和 Platform Lab 媒体 URI。`testEvidence` 只指向相关测试源码，
不表示这些测试已在本次运行，也不表示真实服务或目标平台已验收。生成 API 包自身不发请求，
须由消费端装配；其 OpenAPI 来源在 `tool/openapi/PROVENANCE.json` 单独追溯。

Labs 的实际边界是开发演示：`developmentOnly: true` 只允许与 `template: true`、
`securityPolicy: development_only` 一起使用。默认 HTTP fixture 仅登记 development
Host，不编造 staging/production Host 或 TLS 结论。运行时 WebSocket、图片、媒体 URL
以 `hostPolicy: runtime_supplied`、`hosts/tls: null` 明确记录；这项声明不代表 URL
已经过生产安全校验，也不会让其他源码里的未登记字面量 origin 通过。接入实际产品前须用
真实环境、URL 策略、归属和验证替换开发声明，`template: false` 会拒绝这些样例条目。

模板仓库保留 `"template": true` 以允许示例域名和示例负责人。实际项目采用时必须改为
`false`，正式清单中的 owner、provider、安全策略和测试证据不得保留占位文本。

接入厂商 SDK 时，可以参考 `egress_platform_sdk_entry.example.json`。复制后必须替换：

- `provider`：真实厂商或 SDK 名称；
- `securityPolicyDetails`：TLS、证书、升级、隐私与安全响应责任；
- `testEvidence`：仓库内真实存在的测试/评审路径或 HTTPS 证据 URL。

示例里的占位证据故意不存在，未替换时正式 manifest 不应通过门禁。

Android 的域级明文访问只能放在已知非生产 source set，并在
`nativeSecurityExceptions` 中登记负责人、批准人、到期日、证据和配置文件
`configSha256`。配置内容发生变化后，旧批准会因哈希不一致失效；production
source set 不接受此类例外。

远程证据 URL 必须是稳定、无 userInfo、无 query、无 fragment 的 HTTPS 地址。
需要认证、页面选择参数或临时签名的评审材料，应改用直接资源地址或仓库内脱敏证据。

旧项目迁移时，将 `migration.enabled` 改为 `true`，并把 `migration_manifest.example.json` 复制为实际清单。只有在接口级证据、默认新栈和 Legacy 清零条件同时满足后，才能宣称迁移完成。
