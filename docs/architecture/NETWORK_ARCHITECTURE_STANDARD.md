# Flutter 网络架构标准

本标准适用于启用网络能力的 Koi workspace，规定依赖边界、装配、契约来源、出口登记和验证。认证、OpenAPI、多 Host、刷新、下载或其他协议均按产品需求加入；最小项目和离线工具不因继承此文档而增加网络依赖。

## 分层与装配

业务页面通过 provider、UseCase、Repository 或 Gateway 消费数据，不直接取得 Dio、Koi runtime 或生成 Client。生成 API 包保留传输 DTO 与客户端，项目适配层负责请求执行、错误归一化及 DTO 到业务模型的映射。

```text
presentation → application / domain contract
data implementation → domain contract + network adapter + generated API
composition root → data implementation + network adapter
network adapter → generated API + koi_network
generated API → Dio + Retrofit
koi_network → Dio
```

这些箭头表示编译依赖。生成包不依赖或重导出 Koi、项目 network 包或 App；由宿主在运行时注入已配置的传输客户端。domain 不依赖传输响应包装。共享 package 不反向依赖 App，业务模块不导入其他模块的实现。

单 App 的装配与策略放在 `core/network/` 或 bootstrap，多个 App 确实共享时再下沉为项目 network package。Feature provider 统一放 `presentation/providers/`，宿主装配 provider 放 `core/providers/`；业务编排仍可位于 application。目录、状态和模块规则以 [架构契约](ARCHITECTURE.md) 为准。

Composition root 的职责是解析显式运行环境、配置具名后端、创建客户端和 Repository/Gateway，再通过强类型依赖注入消费方。不要建立字符串加 `dynamic` 的全局 Client 注册表。后端 key 用于装配，业务调用使用有类型的端口。

项目可使用 `AppNetworkContainer` 持有业务依赖，其公开字段应是 Repository/Gateway，不把客户端容器暴露给 Presentation。创建资源者拥有释放责任；App、测试容器和独立会话需明确关闭顺序。

## 当前 bootstrap 的能力与边界

`koi_api_bootstrap` 公共入口使用纯 Dart 配置和契约，不泄漏 Dio 或 koi_network 类型。`KoiApiBootstrapOptions` 以 `baseUrl` 和 `primaryBackendKey` 声明主后端，通过 `additionalBackends` 中的 `KoiBackendDefinition` 声明其他具名后端；runtime 的 `backendKeys` 提供声明清单。

Native composition root 可通过独立的 `koi_api_bootstrap_native.dart` 入口调用 `buildKoiApiClient`，按 backend key 将受管 Dio 注入生成客户端。平台无关代码和 Web 入口不得导入该 Native 装配库。已释放或被替换的 runtime 不能继续创建客户端；释放前须取消或等待在途请求结束。

同一个 runtime 的所有 Host 共用一组 bindings、请求编码、TLS、日志、刷新和白名单策略。当前 koi_network 的 adapters、encoder/parser 及刷新状态具有全局属性，多个 module key 不代表独立认证域。只有会话、编码、envelope 和策略兼容的后端才能共用 runtime。独立 Token、第三方协议或不兼容 adapter 应使用隔离的 Gateway/Transport，并登记原因和测试证据，不为不同 Host 反复改写全局 bindings。

Native 为每个受管后端安装 session-aware 401 保护，按请求 token 和 session revision 隔离迟到的认证失败。认证样例有安全 Token 存储，但没有真实 token refresh 或跨进程用户会话恢复；不能将配置开关当作这些能力的实现。

Web 后端仍为 no-op：它保留后端声明并校验配置，不提供真实 HTTP 客户端。真实 Web API 必须另有实现及浏览器验证。生成客户端可以具有 Web 编译能力，但这不证明当前 bootstrap 已接通 Web 网络。

## 环境与安全

显式配置环境，不用 Debug/Release 推导 development/production。当前 bootstrap 接受 dev/development、test/testing、staging、prod/production；未知环境、空 Host、重复 key 或不合法 URL 应拒绝启动。

- base URL 可以包含固定 path prefix，不得嵌入 userInfo、query 或 fragment。
- staging/production 要求 HTTPS 并验证 TLS 证书；production 禁止原始请求/响应日志及内部调试日志。
- Android production 禁止明文流量；开发域级例外仅能在非生产 source set 中登记负责人、批准人、到期日、证据和整个配置文件的 SHA-256。
- WebView 不得无条件接受无效证书。动态 URL 按 scheme、origin、路径和用途解析检查，不能用字符串 `contains` 判断可信域。
- Token 使用平台安全存储；密钥、原始凭据和敏感正文不写入仓库、日志或分析事件。
- 下载和远程素材按需求验证来源、大小、MIME、缓存、落盘路径及哈希/签名；第三方传输不得自动携带业务认证 Header。

生产日志约束同时覆盖配置开关与 koi_network 的全局调试状态。teardown 应清理受管状态，避免开发 runtime 的调试配置泄漏到后续生产 runtime。

## 请求与会话策略

动态 Token、租户、区域和平台 Header 在 adapter/header builder 中注入。认证白名单按规范化的 origin/path 匹配，不能在页面拼 Header 或修改共享 Dio。

有可变会话时，Token、用户或租户切换应递增 session revision，取消或隔离旧请求结果并清理会话资源。并发 401 的会话失效处理应合并，防止重复清理或导航。刷新只有在真实协议、失败语义及并发测试齐备后才启用。

默认不做无差别自动重试。写请求默认单发，需要重试时提供幂等键或服务端去重契约；其他请求也依据真实业务语义判断，GET 不自动等于无副作用。登录、刷新、握手、流和文件传输分别确定策略。

连接、发送和接收超时按后端基线与操作配置。搜索、页面销毁、账号切换和流式连接需支持取消或拒绝迟到结果。基础设施归一化传输错误，Repository 解释业务含义，Presentation 决定展示；网络包不直接依赖具体页面、Toast 或路由。

如使用 `KoiTypedResponse<T>`，在项目 adapter/executor 适配生成的 envelope；不要为实现该接口而让纯生成包依赖 Koi。

## OpenAPI 与模型

采用 OpenAPI 的服务需记录来源 URL 或本地契约性质、获取时间/版本、SHA-256、parser 名称与版本、配置、输出包和可重复命令。输入及配置通常放在根目录的 OpenAPI 工具目录，并通过 `PROVENANCE.json` 登记。

本地演示契约、服务端契约和兼容 overlay 必须区分。overlay 说明用途、负责人、已验证差异与移除条件；不能发明业务含义。parser 消费完整有效的契约；如果 overlay 只是 patch，先通过可复现步骤生成完整快照。

OpenAPI 生成客户端与 build_runner 生成 Dart part 是两个阶段。登记了 OpenAPI 输入的项目通过 `python3 blueprint.py check generate` 执行两阶段；`check generate-check` 还对 parser 生成的普通 Dart 源码做前后字节比较，发生漂移则失败，未入库 part 仍重新生成。两条命令都会写文件。生成源码不手改，修复输入、配置或生成器后重生成。详见 [生成 API Skill](../../.agents/skills/add-generated-api-package/SKILL.md)。

API DTO 是接口边界模型，不自动等于领域、缓存或 UI 状态模型。替换旧模型前检查所有消费者、缓存反序列化、另一 Host 和界面可变状态，并用真实匿名化 fixture 与字段投影测试验证等价。兼容投影只承载必要差异并说明移除条件。

蓝图的 Admin OpenAPI 是本地演示契约。生成包和 fixture 测试用于验证生成/消费边界，不证明接通任何生产服务，也不作为新项目默认的认证或后端。

## 网络出口清单

启用联网能力的项目在 egress manifest 登记实际出口，包括 Koi 承载的 API 及所有非 Koi 传输。未启用网络的项目可以没有 manifest，或使用空 entries；不得为通过模板门禁虚构出口。

蓝图的模板清单可以使用 `template: true`，每个样例仍须对应实际能力并说明开发期范围。真实项目采用时改为 `false`，补齐负责人、provider、安全策略和测试证据。模板中的 Host 或策略说明不是生产配置。

| 能力 | 推荐边界 | 传输选择 |
| --- | --- | --- |
| 适合 OpenAPI 的受管 REST API | 生成 Client + Repository | 默认采用 Koi；例外说明原因 |
| AI/SSE/WebSocket/其他流 | 明确的 Gateway | 按协议选择，必须可注入与取消 |
| 上传/下载 | TransferGateway | 专用客户端和认证/生命周期策略 |
| 图片、SVG、音视频 | 资源/播放 Gateway 或 Policy | 可由对应插件执行 |
| WebView | ExternalContentPolicy | 约束 scheme、Host、跳转和证书 |
| 原生/第三方 SDK | PlatformGateway | SDK 的内置网络能力也登记 |

统一网络架构要求可追溯的装配、策略与验证，并不要求播放器、WebView 或厂商 SDK 使用 Retrofit。独立认证域、GraphQL/gRPC 或其他已证明不适合 Koi 的协议可以保留长期 Transport，记录负责人、原因、安全策略和证据。迁移期 Legacy 另列退出条件，不把长期架构选择当作待删除代码。

仅开发环境使用的本地服务、运行时地址和演示插件应按真实适用范围登记；没有 staging/production 实现时不要编造 Host。蓝图的 `developmentOnly: true` 仅与 `template: true`、`securityPolicy: development_only` 一起使用；运行时样例地址通过 `hostPolicy: runtime_supplied` 声明，而不是填入假 Host。真实项目的 `template: false` 会拒绝这些开发样例声明；实际动态出口需要可执行的 URL、凭据和 TLS 策略及测试。

## 验证与证据

每个启用后端按能力验证 method、URI、query、Header、body、成功/失败 envelope、DTO fixture、错误映射、超时、取消与资源释放。有认证时增加并发 401、旧 token/revision 隔离；有刷新/重试时增加相应 single-flight、失败和幂等测试。

有 egress manifest 时，`python3 blueprint.py check network` 执行静态 validator；蓝图源仓另执行 JSON Schema 与 validator 黑盒正反例，下游校验自己的清单。`python3 blueprint.py validate` 同样调用此阶段；没有 manifest、活动 OpenAPI 配置和生成 API 包的离线项目返回 NOT_RUN。有活动生成输入或 API 包却缺少 manifest 时失败，不能用删除清单绕过门禁。

静态检查扫描 App、packages、modules 和 examples 中的相关网络依赖与常见原生安全配置，校验出口结构、环境 Host/TLS、生成包依赖、OpenAPI provenance 哈希、活动 parser 配置及输出位置，并可检查迁移清单。合法 Transport 构造位置可通过精确文件清单声明；该声明不豁免 UI 边界、TLS 或 URL 规则。

这些检查不证明所有动态 URL、重定向、插件或 SDK 出口都已发现，不代替生成零漂移、真实认证/并发/取消、服务联调或目标平台验收。网络阶段 PASS 只代表当前静态规则和测试通过。完整验证口径见 [测试策略](../test_strategy.md) 与 [工具清单](../tools.md)。

## 存量迁移

1. 盘点 Host、实际可达接口和非 OpenAPI 出口，保存现状行为证据。
2. 建立出口清单、来源记录和契约 fixture，明确有效例外。
3. 在 composition root 装配依赖，先保持已验证行为和认证/平台边界。
4. 按可达业务链路迁移协议、Repository/Gateway 和模型投影。
5. 完成生成漂移、静态边界、行为测试及对应平台验证，再切换默认实现。
6. 删除已无消费者的 Legacy Client、重复适配和迁移开关。

每个 Legacy 例外要有负责人、原因和退出条件，迁移清单应逐步收敛。迁移完成需要实际默认调用链、安全/会话行为和平台证据，不能仅凭文件数、静态门禁或设计文档宣称完成。
