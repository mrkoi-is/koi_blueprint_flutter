# 本地优先与桌面应用

适用于本地文件、数据库、原生引擎和长任务。沿用 [架构契约](ARCHITECTURE.md)，依据真实 IO 与编排职责建层。

## Feature 与运行时

本地 repository 实现在 `data/` 或共享基础设施包；命令、会话、任务状态在 `application/`；领域模型与端口在 `domain/`；页面在 `presentation/`。`data` 和 `application` 可共存。如果 Studio 与 CLI 共用存储/引擎，保留一份共享实现，在各宿主组合根注入，不再复制 Feature data 实现。

应用级 Runtime/Coordinator 可统一持有长生命周期设施，但必须明确拥有者和释放范围。Riverpod 暴露可观察状态，而不仅是服务定位器。既有 ChangeNotifier/Stream 在 provider 边界适配，订阅清理见 [状态规范](state-management.md)。

## IO 与任务

- Widget 和 provider 同步计算路径不执行阻塞文件/进程 IO；通过异步 repository 读取并形成模型。
- 长任务通过不可变状态/进度事件暴露；队列、取消、重试和过期结果判断在 application/service。
- 文件路径、时钟、引擎和存储经构造器或 provider 注入；测试使用临时目录和替身。
- 会话切换/销毁后异步结果不得写回新状态。停止订阅不等于取消外部进程，两者分别处理。
- 持久化格式、原子保存和恢复策略属于产品契约；新蓝图不强制数据库，已有格式变更须有迁移测试。

## 桌面 UI

跟随系统主题，颜色使用主题 token；点击、键盘焦点和 hover 有可见反馈。窗口缩小时布局保持可用，长内容可滚动。窗口关闭需保存草稿时由宿主注册生命周期钩子，业务保存由应用层执行。

桌面示例只能证明对应测试和构建结果。原生引擎、外部工具、实际设备或其他 OS 的运行效果另行验证。
