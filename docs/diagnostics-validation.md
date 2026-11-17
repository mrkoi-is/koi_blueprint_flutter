# diagnostics v2 验证记录

日期：2026-11-15，America/Los_Angeles。代码实现、Android release 补验与设备收尾均已完成。

## 实现与本地验证

默认安装到新建 minimal/workbench 项目；显式 capabilities 配置仍代表完整选择。Talker 统一写入宿主唯一的 20 MiB 存储，设备和 LAN 网页共享日志、网络请求、脱敏、过滤、详情及 NDJSON 导出。release 在“关于”连续点击版本号七次进入。

| 范围 | 结果 |
| --- | --- |
| 源仓库完整门禁 | PASS，覆盖率 82.98%（10432/12572） |
| minimal 生成项目完整门禁 | PASS，覆盖率 81.15%（2604/3209） |
| workbench 生成项目完整门禁 | PASS，覆盖率 83.08%（5157/6207） |
| 模板继承检查 | PASS，minimal/workbench |
| Android arm64 release 构建及最终安装 | PASS |
| Web release 构建 | PASS，Web 不提供 TCP 服务端 |
| 最后修复的 LAN 超长日志换行 | 4 项定向测试、分析、格式检查及真实 Chrome 桌面/窄屏布局均 PASS |

完整门禁包括生成、格式、架构、分析、成员测试、Chrome 测试、覆盖率；源仓库另含 API Web 编译/Node 冒烟。诊断页面 ARCH010 字段数提示已审阅：筛选、分页与导出反馈属于页面瞬态状态，宿主继续拥有存储、采集与 LAN 生命周期，其他架构问题仍作为失败处理。

## Android release 实测

设备为 Pixel 6a / Android 17，测试包 `dev.koi.diagnostic_probe_app`，target SDK 36。已查看真实 HEAD 请求的状态码、响应头与耗时，设备和 LAN 网页均可查看；示例地址返回 404，诊断完整记录该响应。

系统电池优化豁免弹窗已出现并授权。升级到最终 release 后，84 条旧事件逐条比对全部恢复。独立验收 APK 主动调用 AppLogger、print、debugPrint，三类普通日志均出现在设备和手机提供的 LAN 网页，测试 token 已脱敏。验收发声及锁屏探针仅加入临时测试工程，最终 APK 和蓝图模板不包含这些探针。

最终安装构建标识：`e8647fee1d71583e4fd25c5e982fcd651c90fb156ce273e731d9d132869ef755`。APK SHA-256：`dce0263caa43ce67207e9762a82446b304cb47bb223971c40462c1353809eb8e`。最后一次改动是网页长日志换行样式；1280 像素桌面两栏无重叠，390 像素窄屏无横向溢出。该样式修复另经定向测试和真实浏览器验证。

## 连续锁屏与后台 LAN

最终依据为 `android-native-lockscreen-result.json`：

- 时间：2026-11-15T11:02:11.385284Z 至 2026-11-15T11:32:26.386358Z（UTC）。
- 连续锁屏 1815.001 秒，即超过 30 分钟；122 个 Android 原生样本全部通过。
- 每 15 秒只读采样 KeyguardManager/PowerManager 状态、系统单调时间及 Flutter 生命周期。keyguardLocked/deviceLocked 始终为 true，应用 lifecycle 始终为 paused，原生采样无超过 45 秒的空档。
- 此轮 309 次电脑侧 LAN 查询全部 HTTP 200；浏览器记录版本未经手动刷新自动增加，实时日志正常。
- 锁屏画面期间曾亮起，但设备未解锁、应用始终在后台；没有将画面亮起误判为解锁。
- 观察到 connectedDevice 前台服务及 CPU/Wi-Fi 锁持有。本次使用 USB 连接充电，未覆盖断电后的深度 Doze 或其他厂商设备。

较早依赖 ADB 的采样和屏幕关闭实验保留原始日志，不作为最终锁屏结论。原生探针只读系统状态，没有修改 USB 安全设置；最终 APK 已移除探针。

## 设备收尾

全部完成：

1. 诊断 LAN 已停止，旧端口不可连接，前台服务、CPU 锁及 Wi-Fi 锁均已释放；再次启动时旧访问凭证返回 401。
2. FlClash 取消 DiagnosticProbe 勾选并保存，关闭访问控制，重新应用 VPN 配置。VPN 保持开启、Rule/Blacklist 模式保留，系统 UID 范围已恢复为 `0–99999`，没有遗留测试排除项。
3. Gboard 已恢复原中文子类型 `617035939`。
4. 最终 APK 已重新安装并通过版本页核对构建标识，隐藏诊断页可进入，LAN 保持关闭，没有自动启动前台服务。

通知及后台运行权限保持已授权。iOS/其他桌面平台的真实运行未在本次执行。

## 本地证据

`build/diagnostics-validation/` 为本地忽略目录，包含最终 APK、构建清单、`result.json`、三份完整门禁日志、原生锁屏样本/结果、设备导出、资源释放及设置还原记录、浏览器布局检查、设备和 LAN 截图。`release-probe-source/` 保存临时探针源代码与验证脚本。访问凭证不写入此文档。

使用方式见 [诊断能力](diagnostics.md)。
