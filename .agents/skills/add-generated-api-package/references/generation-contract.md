# API 生成执行契约

记录 schema 来源/版本或本地 fixture、生成器及版本、命令、输出目录、生成文件策略和消费方。不要将真实认证信息放进可分享 fixture 或文档。

两个阶段分开：OpenAPI 工具根据 schema 输出请求/客户端源码；build_runner 根据 Dart 注解产生 part 文件。`generate` 能运行 build_runner 不代表完成 OpenAPI 生成。

新增包配置 `resolution: workspace`，登记根 workspace 和消费依赖。平台无关契约避免泄漏 Dio；Native/Web 实现分别验证，Web no-op 不是可用后端。

验收包括干净重生成、fixture 解析、错误映射、消费方编译、目标平台构建，以及已实现认证场景的 session/revision 防护。网络服务尚未提供时明确标记实现缺口，保留可测试替身继续本地实现。
