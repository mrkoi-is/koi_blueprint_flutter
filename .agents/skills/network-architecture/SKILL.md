---
name: network-architecture
description: 新增 Host、网络策略、外部出口或迁移旧网络，并验证装配、会话隔离和出口清单。
---

## 目标
为已启用网络能力的项目建立可追溯、可替换的传输边界，不给最小项目或离线工具强加网络依赖。

## 决策
先确认目标平台、Host、实际可达调用、认证域、协议和资源拥有者。只增加生成包时使用 add-generated-api-package；新增后端、调整网络策略或迁移多条调用链时使用本技能。

## 流程
1. 读 [网络标准](../../../docs/architecture/NETWORK_ARCHITECTURE_STANDARD.md)，盘点业务 API 及资源、下载、流式连接、媒体、WebView、SDK 的实际联网入口。
2. 明确环境、认证域、请求编码和 envelope；在宿主 composition root 装配具名后端，通过强类型 Repository/Gateway 注入消费方。
3. 多 Host 共用 Koi bindings 前核对会话和 adapter 策略兼容性；独立认证域或不兼容协议通过明确的 Transport/Gateway 隔离。
4. 在 egress manifest 登记已启用出口、负责人、Host/动态 URL 策略及测试证据。实际项目使用 `template: false`；开发期样例不能冒充生产后端。
5. 采用 OpenAPI 时按 [生成契约](../add-generated-api-package/references/generation-contract.md) 登记输入、配置、哈希和生成命令。
6. 覆盖请求边界、错误、取消、资源释放，以及已启用认证能力的并发和旧会话隔离；执行受影响测试与适用门禁。

## 核心规则
- 页面和展示状态只消费业务端口，不获取 Dio、Koi runtime 或生成 Client。Feature provider 仍放 `presentation/providers/`，宿主装配 provider 放 `core/providers/`。
- 公共 bootstrap 不泄漏 Native 传输类型；Web no-op 不代表真实网络能力，未实现 token refresh 时不宣称已支持。
- 写请求默认不自动重试；其他请求也按业务幂等性决定，不能仅根据 HTTP method 判断。
- Token/会话变化必须隔离旧请求结果；创建资源者负责释放，借用者不能销毁共享服务。
- 网络、安全和生命周期策略属于基础设施与业务边界，不在页面拼 Header 或修改全局客户端。

## 验证
有 manifest 的项目执行 `python3 blueprint.py check network`；它提供静态扫描，蓝图源仓另执行 schema 与 validator 黑盒回归。OpenAPI 接入另执行 `check generate` 和 `check generate-check`，然后执行受影响行为测试和 `python3 blueprint.py validate`。实际服务、目标平台构建与设备运行分别报告；静态门禁通过不等于迁移或生产验收完成。
