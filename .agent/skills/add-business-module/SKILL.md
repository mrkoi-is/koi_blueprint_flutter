---
name: add-business-module
description: 创建独立业务 module 并通过 koi_modules 接入宿主路由、注入和会话切换。
---

## 目标
把需要独立依赖、测试或会话边界的业务域接入宿主；普通页面仍使用 Feature。

## 决策
确认 module id、公开契约、宿主导航与会话资源。共享服务由宿主持有，模块只拥有自身会话。

## 流程
1. 读 [模块契约](../../../docs/architecture/modules.md) 和 [模块宿主样例](../../../docs/examples.md)。
2. 运行 `python3 blueprint.py module <name> --workspace <directory> --dry-run`，核对后生成。
3. 登记 workspace 与宿主依赖，提供模块描述和 session 工厂；跨模块数据通过公共契约。
4. 由宿主构造不可变 catalog 并一次组合路由，通过 overrides/构造器注入共享服务。
5. 切换前清理旧 session，拒绝旧会话的迟到结果；测试同 ID、路由冲突和重复切换。

## 核心规则
- module 不反向依赖宿主，也不导入其他 module 实现。
- 不建立进程全局可变 registry；catalog 是编译期可知的组合。
- 宿主 router 稳定，切模块不随意重建整套路由状态。
- dispose 只清理拥有的会话资源，不能关闭借用的宿主服务。
- session 工厂/清理必须有界；串行切换不能绕过永不结束的 Future，guard 也不会取消它。

## 验证
验证宿主可导航到模块、参数可解析、注入可替换，旧 async 结果不能污染新 session，重复 dispose 行为明确。公开接口以 [模块契约源码](../../../docs/examples.md) 为准。
