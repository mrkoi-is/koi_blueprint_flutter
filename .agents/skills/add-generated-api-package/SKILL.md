---
name: add-generated-api-package
description: 接入 OpenAPI 生成包与网络消费适配，记录可重复输入、生成命令和真实客户端边界。
---

## 目标
建立可重复生成的 API 包，使业务代码通过稳定仓库/适配层消费。

## 决策
先确认本地 schema 或授权接口来源、生成器版本、目标平台、认证与 envelope 形态。蓝图提供认证/网络示例，不代表已接通具体业务 API。

## 流程
1. 读 [生成契约](references/generation-contract.md)，记录输入、版本、命令和输出目录。
2. 创建 `<project>_api` 与按需的 `<project>_network`，按共享包流程登记 workspace 和依赖。
3. 使用所选 koi_swagger_parser 版本实际支持的命令生成；不要猜参数，也不要把 build_runner 当 Swagger 输入生成器。
4. 适配层负责 envelope、错误、token/session 和平台实现；repository 将传输模型映射到业务模型。
5. 注入宿主，测试解析、错误、认证过期和平台边界，再运行生成/分析/测试。

## 核心规则
- 生成文件不手改；改 schema/配置/生成器后重生成。
- presentation 不直接调用 Dio；公共契约不泄漏请求栈实现。
- Web no-op 示例不是真实 Web 网络；token refresh 未实现时不可宣称已支持。
- 认证属于产品需要时才接入，不给离线项目强加账号。

## 验证
保存最小可分享 schema fixture，验证一次干净重生成和消费方编译；真实服务调用与本地 fixture 验证分别报告。
