# Monorepo 契约

根 `pubspec.yaml` 的 workspace 是成员清单的唯一来源；成员设置 `resolution: workspace`。新增 App、module 或 package 必须登记、解析依赖，并确认生成/分析/测试发现它。不要另写一份脚本硬编码清单。

```text
apps/       宿主与组合根
modules/    独立业务模块（按需）
packages/   公共契约、基础设施、UI 等稳定共享能力
examples/   蓝图维护用的可运行示范
```

## 依赖方向

- App 可以依赖 module 和 package；多个 App 通过 package 共享，不互相引用。
- module 依赖公共契约/基础包，不互相 import 业务实现，也不依赖宿主 App。
- domain 契约不依赖 IO、UI 或实现；实现依赖契约，由宿主注入。
- UI 包不依赖业务 repository、router 或运行时；业务专用 Widget 留在 Feature。
- 包的公开 API 只暴露消费方需要的类型，不把 Dio、平台句柄等实现细节外泄。

`koi_auth` 的认证模型保持独立；`koi_modules` 提供模块会话契约，不负责实际 App UI。两者均是按场景引入的能力，而不是创建空项目的必选依赖。

## 自动化范围

质量工具从 workspace 获取成员，区分 Dart/Flutter 包、生成器和目标平台。每个可执行成员都提供测试；生成源码排除覆盖率，手写源码不能靠漏导入测试躲过覆盖率检查。样例不是发布产品，但同样需要独立解析、分析和测试。

跨平台 Python 入口为 `blueprint.py`，Makefile 和 shell wrapper 作为已有用户的便捷入口。CI 和本地调用同一逻辑，平台构建由匹配的 runner 执行。
