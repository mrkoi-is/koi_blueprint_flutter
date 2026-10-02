# Device Lab

本样例实现三个可独立安装的能力：`onboarding`（首次配置）、`incoming-intents`（外部入口）与 `lan`（成对设备的摘要和有限命令）。它们共用纯 Dart 队列与设置契约；首次配置和外部入口不依赖 Bonsoir、WebSocket，也不会启动监听。

- 首次配置保存语言、目录与完成/跳过状态，支持中断后恢复和重新配置。目录实际用于下一次文本选择。独立入口由 App 拥有的英语、简体和繁体 ARB 驱动；安装时合并到宿主 ARB。
- 入站队列先等待持久化恢复，再检查草稿是否允许离开。重复事件、未知 URI、保存失败和页面尚未创建都有明确处理。`koi://tasks`、`koi://document?id=welcome`、本地文本文件，以及 Web `?koi-intent=koi%3A%2F%2Ftasks` 使用同一处理链。Web 插件只提供初始 URL。
- Android 配方把 `ACTION_SEND` 文本/文件转换为统一入站事件；`content://` 通过宿主生成的 MethodChannel 与 ContentResolver 读取真实字节，限制 256 KiB，保留原系统访问权限的约束。macOS 配方生成 `openFiles` 回调，在有效的安全作用域内复制文本到应用临时目录再交给同一 importer。iOS 注册 URL 与文本文件打开类型；未实现独立 iOS Share Extension。
- LAN 只有用户点击后才启动 Bonsoir 发现或桌面 WebSocket 服务。默认测试监听 `127.0.0.1`；“允许局域网配对”才绑定本地网络地址并发布 Bonjour。浏览器/移动端作为前台客户端。配对码、代次与关联 ID 隔离连接，断线后有限退避重连，退出取消重试并等待已接受操作。
- 可执行命令只有摘要、暂停摘要刷新和恢复摘要刷新；摘要包含资料标题、字符数与任务状态，不同步正文或文件，也不执行任意远程命令。

宿主通过 `CapabilityLifecycle` 统一准备退出与关闭。准备保存失败会取消退出，已打开的服务仍可继续使用；页面离开则注销自身生命周期并关闭资源。

## 验证

统一 workspace 依赖与生成完成后：

```sh
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/application test/data test/incoming test/local_setup test/device_page_test.dart
../../.fvm/flutter_sdk/bin/flutter test --no-pub --platform chrome test/browser/device_settings_browser_test.dart
../../.fvm/flutter_sdk/bin/flutter build web --no-pub
# repository root: native source overlays, not actual platform execution
python3 -m unittest tool.tests.test_device_capabilities
```

已验证：实际 loopback WebSocket 配对/错误码/断线重连、Native 设置文件与真实 UTF-8 文件、浏览器 localStorage、冷/热事件队列、错误重试与草稿保护、模块资源清理。原生 ingress planner 测试验证修改保留、幂等、冲突拒绝和 Android ContentResolver 的 Dart 通道契约。

Android 分享选择器、iOS 文件打开、macOS Finder 文件打开、Bonjour 跨设备发现以及 Windows/Linux 协议注册仍需目标系统端到端验收；配置文件或通道替身测试不能代替这些结果。Windows/Linux 生成显式本地协议注册脚本，安装能力本身不会执行脚本或修改当前电脑的协议关联。参考 [app_links 平台接线](https://github.com/llfbandit/app_links/tree/main/doc)。
