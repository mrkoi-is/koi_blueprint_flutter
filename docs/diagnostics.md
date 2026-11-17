# 标准诊断能力（diagnostics v2）

新建 minimal/workbench 项目未提供 capabilities 字段时默认安装；显式 `capabilities: []` 关闭，非空列表代表完整选择。旧工程不追溯安装默认项，使用 capability add 或升级报告审阅变更。v1 → v2 保留原 ID 和旧日志读取，不能通过改 receipt 版本跳过迁移。

App 启动即持续采集 AppLogger、print/debugPrint、Flutter/Dart 主 isolate 异常、Riverpod 失败及已接入客户端的网络请求。release 在“关于”连续点击版本号七次打开诊断，间隔超过三秒重置。日志和网络请求页支持查询、详情和 NDJSON 导出。原生插件的系统 logcat、其他 isolate 和未接入的第三方网络 SDK 不属于自动采集范围。

Talker 5.2.0 是统一采集入口；自身 history 和重复 console output 关闭。唯一 DiagnosticStore 由 AppDiagnostics 拥有，设备 UI、LAN UI、持久化均借用该存储。网络适配器仅生成安全快照，不保留 Dio/流对象；network/images 的 Transport 和 koi_api_bootstrap 的 Dio 各接一次。外部客户端可通过 koi_core 的 Diagnostics.startNetwork 接入，完成时调用 response/finish。

历史默认 20 MiB，超限淘汰最旧记录；请求和响应文本样本上限 64 KiB，二进制只显示元数据。凭证键在采集时脱敏。Native 使用 NDJSON 轮转，Web 使用 IndexedDB。持续增量保存，不依赖退出回调；异常终止时尚未写盘的尾部记录可能丢失。存储损坏保留原始文件并显示降级状态，不能让诊断故障阻止业务启动。

局域网查看由诊断页手动开启，选择设备局域网接口后显示地址及随机访问凭证。在同一 LAN 的浏览器打开地址并输入凭证。网页、查询、实时更新和导出不依赖外部服务；查询和订阅需要会话凭证。每次开启更换凭证，停止后关闭连接。HTTP 仅用于本地诊断，不提供互联网访问入口。

Android 开启 LAN 时才启动 connectedDevice 前台服务并持有 CPU/Wi-Fi 锁，切 App/锁屏继续访问；关闭即释放。通知/电池优化授权由系统处理，系统或厂商仍可能终止进程。从最近任务移除、强制停止、明确退出后不自动恢复服务。插件锁定 flutter_foreground_task 11.0.3：stopWithTask 只在 Manifest 设置，不传 Dart 同名 option（该版本会在 Activity pause 时停服）；不传任务 callback，不搬运诊断状态至第二 isolate。不要与宿主其他功能争用同一前台服务。

iOS 进入后台关闭 LAN；桌面关闭 App 时停止。Web 可查看本地日志但不能启动 TCP 服务端。Android 当前 target 36；未来提升 target 时需重新检查局域网权限要求。

验证必须分别记录单元/集成测试、生成项目门禁、release APK 构建与 Android 真机运行。锁屏至少 30 分钟并从另一台设备查询才能声明后台验证通过；没有设备时保留 NOT_RUN。

同网段仍连接超时时，检查 VPN 的应用访问控制。本次 FlClash 全应用 VPN 环境中，临时排除诊断宿主 App 后，电脑才能经 Wi-Fi 访问；完成诊断后可恢复原分流设置。
