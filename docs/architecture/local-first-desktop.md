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

## 工作区所有权与关闭

Workbench 采用单写者：Native 文件锁覆盖当前拥有者 isolate 与其他进程，Web Lock 覆盖同源标签页/worker。Native 存储只由宿主拥有者 isolate 装配，后台 isolate 使用宿主提供的消息端口；POSIX 文件锁不能作为跨 isolate 互斥。第二会话在加载/恢复/清理之前失败并可重试。存储不支持安全锁时明确失败，不降为可写内存模式。

持久化 storageVersion 独立于 UI/任务 snapshot.revision；旧快照缺失时从零读取。保存比较 expectedVersion，成功事务提交后递增，冲突保留内存内容。所有素材 IO 完成后才释放锁；只有取得独占权的启动流程可以回收上个拥有者的遗留暂存。

正常关闭分为可取消准备与不可逆销毁。准备期间阻止新操作、收尾任务，并消费明确的保存结果；失败恢复可编辑会话。成功之后释放 router/provider/媒体/会话/存储。不能把 await 一个吞掉错误的 Future<void> 当成保存成功，也不能在 dispose 后取消退出并继续显示失效会话。

原生退出由宿主 binding 协调：先等待 Flutter 完成本轮所有退出监听器通知，全部允许退出后，再卸载消费 router/provider 的 Widget 子树并释放它们的拥有者。不能在单个监听器内提前卸载，也不能靠注册顺序或延时推测通知完成；否则本轮快照可能继续调用已释放的监听器。保存失败或其他监听器取消时保留页面与资源；重复请求共享进行中的退出。

## Workbench 内部协作者

WorkspaceSession 继续持有唯一 WorkspaceState、通知流、revision、任务和取消登记。WorkspacePersistence 管理保存队列、防抖与存储版本；WorkspaceImportWorkflow 管理选择器、输入源、读取/校验/暂存/提交；WorkspaceThumbnailWorkflow 管理转换、替换和缩略图清理。内部 access 只读当前状态、提交同步变换与请求保存，不从 Feature 公共入口导出，也不缓存另一份可写快照。

缩略图 workflow 登记完整操作 Future，包含补偿与最后的文件清理；直接 storeThumbnail 和图片转换使用同一 drain 合同。关闭不能只等任务状态变为完成，必须等暂存、提交或删除中的实际 IO 结束，宿主才能释放借用的存储。

保存排队后在实际执行时捕获快照；成功仅确认捕获的文档 revision，不能把保存期间的新编辑标记为已保存。取消补偿先持久化引用变化再删除文件；补偿失败保留可恢复内容并报告失败。关闭等待已开始的 IO 与清理；系统选择器的迟到结果仅释放输入，不再写存储。dispose 的重复调用等待同一清理 Future，借用的存储最后由 bootstrap 释放。

新素材或缩略图引用一旦进入共享 Session，就可能被此前排队的保存持久化。不能用当前工作流自己的保存失败推断文件尚未被引用。取消和普通失败都必须先成功保存去引用的补偿，再删除字节；补偿失败保留文件和可恢复引用。回归应交错“已有保存排队、新引用可见、工作流保存失败”，同时覆盖补偿成功与失败。

MediaPreviewSession 保留队列、代次与播放命令，允许 Flutter foundation 的 Listenable/ChangeNotifier 适配。MediaPlayback 不返回 Widget；MediaKit SDK、订阅和 Web 首帧探测位于 data/media，稳定 Video/key 位于 presentation/media。bootstrap 同时注入工厂和借用的展示句柄，关闭按播放器身份清除句柄。相同素材与布局切换不重建播放器，旧播放器和 source 释放结束后再创建下一实例。

## 桌面 UI

跟随系统主题，颜色使用主题 token；点击、键盘焦点和 hover 有可见反馈。窗口缩小时布局保持可用，长内容可滚动。窗口关闭需保存草稿时由宿主注册生命周期钩子，业务保存由应用层执行。

桌面示例只能证明对应测试和构建结果。原生引擎、外部工具、实际设备或其他 OS 的运行效果另行验证。
