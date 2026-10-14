# OpenAPI 输入与来源记录

生成 API Client 前，把服务端文档或批准的兼容契约放在本目录，并将 `PROVENANCE.example.json` 复制为 `PROVENANCE.json` 后填写真实信息。

最低要求：

- `*.openapi.json`：未经 overlay 的原始契约快照；
- `*.overlay.json`：必要的兼容修正，写明负责人和移除条件；
- `PROVENANCE.json`：URL、获取时间、SHA-256、parser 版本、配置和输出包；
- 生成命令可以在干净工作区重复执行；
- 在线 Swagger 与本地兼容契约必须明确区分。

每个非 `*.example.yaml` / `*.example.yml` 的活动 parser 配置都必须被 provenance
覆盖。`python3 blueprint.py check network` 会用 `koi_swagger_parser` 自身的配置加载器解析 enabled inputs
和 base/api/models 输出目录，并与 `sourceFile`、`configFile`、`outputPackage` 双向匹配；
`parserVersion` 还必须与 `pubspec.lock` 的实际版本一致。远程输入、仓库外文件、
重复输入和多个配置写入同一 API 包都会失败。

实际项目把 egress manifest 的 `template` 改为 `false` 后，provenance 同时禁止
`template_example` authority、`local-template` 来源和示例保留域名，防止模板契约被误当成服务端事实。

存在 `overlayFile` 时，它必须是 parser 可直接消费的完整有效 OpenAPI 快照，活动配置
应指向它；只含 patch 操作的 overlay 必须先由可复现工具物化，不能直接冒充生成输入。

`sourceUrl` 只记录稳定、无 userInfo、无 query、无 fragment 的来源地址。应记录
直接 Swagger JSON URL，不记录带文档选择参数的 Swagger UI；认证信息不属于可提交的 provenance。

生成包或活动 parser 配置存在时，`python3 blueprint.py check network` 会要求提交 `PROVENANCE.json`。

当前 `admin.openapi.json` 是标记为 `template_example` 的本地示例契约，源仓对应 admin.yaml 配置与 koi_admin_api 输出包；新建项目不自动启用它们。`python3 blueprint.py check generate` 会先执行全部非 `*.example.yaml` 配置，再执行各 package 的 build runner。

`koi_swagger_parser 0.2.0` 在 `v1 + split_by_tags: false` 的聚合 Client 中会生成导入别名/字段同名冲突；模板在该问题修复前统一保持 `split_by_tags: true`，并由 `analyze --fatal-infos` 阻止不可编译的生成结果。

`tool/koi_swagger_parser/main.example.yaml` 提供本地契约、生成目录、枚举映射和 unknown fallback 的起始配置。复制并改名后再执行：

```bash
dart run koi_swagger_parser generate --all --config tool/koi_swagger_parser/main.yaml --dry-run
dart run koi_swagger_parser generate --all --config tool/koi_swagger_parser/main.yaml
```

`python3 blueprint.py check generate-check` 会重生成并检查 OpenAPI 普通源码是否漂移；build_runner part 文件保持不提交。新建离线工程只继承工具与示例配置，活动 provenance、parser 配置和出口清单由接入项目建立。
