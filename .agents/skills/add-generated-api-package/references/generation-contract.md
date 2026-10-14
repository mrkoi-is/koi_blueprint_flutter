# API 生成执行契约

记录 schema 来源/版本或本地 fixture、生成器及版本、命令、输出目录、生成文件策略和消费方。输入、parser 配置及兼容 overlay 均记录 SHA-256；overlay 说明负责人、用途和移除条件。不要将真实认证信息放进可分享 fixture 或文档。

两个阶段分开：OpenAPI 工具根据 schema 输出请求/客户端源码；build_runner 根据 Dart 注解产生 part 文件。有已登记 OpenAPI 输入的项目由 `python3 blueprint.py check generate` 串联两阶段，`check generate-check` 还对 parser 生成的普通 Dart 源码做前后字节比较，发生漂移则失败；无 OpenAPI 的项目只执行 Dart part 生成。两条命令都会写生成文件，不能当作只读审查。

对输入、配置和 parser 生成的普通 Dart 源码使用目录内 `.gitattributes` 固定 LF，避免 Windows Git 检出改变来源哈希或造成生成漂移误报。用 `core.autocrlf=true` 的真实 Git 检出验证字节保持一致；不要放宽原始 SHA 或生成字节比较。

OpenAPI 输入与配置通常保存在根目录的 OpenAPI 工具目录下，来源登记文件为 `PROVENANCE.json`；具体文件清单以当前项目登记为准。蓝图内置 Admin 契约是本地演示，不代表真实服务。新项目按需建立自己的契约及生成包，不自动启用此演示后端。

本地兼容输入应标明与服务端事实的差异。parser 必须消费完整有效的契约；overlay 若是 patch，先用可重复步骤物化完整快照。不要仅更新哈希来掩盖来源或生成结果变化。

新增包配置 `resolution: workspace`，登记根 workspace 和消费依赖。纯生成包不依赖消费层或 Koi；平台无关业务契约避免泄漏 Dio。Native/Web 实现分别验证，Web no-op 不是可用后端。

验收包括干净重生成、provenance 哈希与输出目录匹配、fixture 解析、字段投影、错误映射、消费方编译、目标平台构建，以及已实现认证场景的 session/revision 防护。生成源码不能直接取代有缓存或 UI 语义的旧模型，应先验证消费者和序列化兼容。网络服务尚未提供时明确标记实现缺口，保留可测试替身继续本地实现。
