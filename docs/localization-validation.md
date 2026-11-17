# 国际化修复与发布验收记录

日期：2026-11-17（America/Los_Angeles）。范围为 minimal / workbench 蓝图及默认诊断能力，语言为英文、简体中文、繁体中文，目标为 Android、iOS、macOS、Windows、Linux、Web。证据对应国际化修复阶段的工作树（源码指纹 `5e8ec4853b4c23e36d2aa1fcf4f145685862affafa7c79dd6ac17f8867f0ea09`），先于已发布分支的整合，不代表合并后的候选提交已重新执行全部设备测试。最终候选的门禁与 CI 结果另见 [版本记录](releases/v0.3.0-rc.1.md)。三项代码缺口已修复，六端完整国际化验收尚未完成。

## 本轮修复

- 创建器声明 Apple 三语支持；诊断配方将三份 `InfoPlist.strings` 接入 Runner 资源构建阶段。既有自定义译文或权限说明冲突时停止合并并保留文件。
- Xcode/CocoaPods 的注释、排版和对象重排不会破坏本地化资源识别。受控构建准备阶段仅更新原先匹配基线的原生记录，构建前已被用户修改的文件仍保持本地修改状态。
- Android 通知标题、正文和渠道名称采用启动 LAN 时的语言；通过宿主通道修改已有渠道名称，保留渠道 ID、重要性和用户通知设置。
- LAN 网页使用正确的 BCP 47 `lang`，翻译标题及导出失败提示；兼容 `zh_Hant`、`zh-Hant` 和中文地区标签，显式脚本优先。

## 自动化证据

| 检查 | 状态 | 范围 |
| --- | --- | --- |
| Python 定向回归 | PASS，36 项 | 原生资源与冲突保护、CocoaPods 重排、Android 渠道接线、构建准备基线与用户修改保护 |
| Dart 定向回归 | PASS，7 项 | 通知参数、LAN 实际 HTTP 响应与语言匹配；最终通道接线已由完整门禁复验 |
| Chrome 定向回归 | PASS，3 项 | 三语网页 DOM、实际导出失败处理及 320px 布局 |
| 原生包译文查询 | PASS，12 项 | 两模板 × iOS/macOS × 三语；Foundation 显式语言匹配与包内字符串读取 |
| 修复阶段源码完整门禁 | PASS，覆盖率 83.20%（10502/12623） | 生成、格式、分析、架构、模板继承、成员测试、Chrome、覆盖率与 API Web 冒烟；Python 为 40 + 237 项，其中 1 项跳过 |
| 原生引擎界面回归 | PASS，6 个 fixture / 18 个语言检查 | 两模板 × macOS、Android 真机、iOS 模拟器；切换语言、router/session 保留与恢复系统模式；workbench 使用真实临时文件重开偏好 |
| Android 真实通知 | PASS，3 种语言 | 使用真实 NotificationManager 读取渠道名、已发布通知标题与正文；初始渠道重要性 2 保持不变 |
| 构建后能力重入 | PASS，两模板 | 最终工程构建后再次规划安装 diagnostics，变更文件为空 |

包内资源查询使用 macOS Foundation 显式选择语言，不等于系统权限弹窗测试。原生界面测试在真实引擎中设置应用语言，未修改系统语言；文件偏好重新打开不等于跨进程冷启动。macOS 测试工具报告无法将窗口置前，界面/状态断言通过，人工视觉检查未覆盖。Android 通知额外在真机读取了系统通知状态，不仅依赖平台替身；初始权限由测试准备阶段授予，未验证授权弹窗。

## 六端矩阵

每行均涵盖两种模板。Windows/Linux 目录已生成，不据此推断目标主机构建成功。iOS 构建不签名，macOS 使用本地临时签名，不代表分发签名或公证完成。

| 平台 | 修复阶段工程生成 | 修复阶段本机 release 构建 | 完整三语系统/UI 实测 |
| --- | --- | --- | --- |
| Android | PASS | PASS | PARTIAL：Android 13 真机，两模板三语界面及真实诊断通知通过 |
| iOS | PASS | PASS（无签名） | PARTIAL：iOS 26.5 模拟器，两模板三语界面通过；真机未执行 |
| macOS | PASS | PASS | PARTIAL：macOS 27.0.1，两模板三语引擎界面与文件偏好通过 |
| Windows | PASS | NOT_RUN：缺少 Windows 主机 | NOT_RUN |
| Linux | PASS | NOT_RUN：缺少 Linux 主机 | NOT_RUN |
| Web | PASS | PASS | PARTIAL：Chrome 诊断网页已验证；完整模板操作和 Safari 未执行 |

## 余下发布验收

在各平台按 [平台验收](platform-acceptance.md) 使用隔离测试工程执行，并分别登记结果：

1. 系统语言依次设为英文、简体、繁体，检查冷启动、运行中变化及不支持语言的回退；Apple 原生提示按 OS 为 App 选择的语言验证。
2. workbench 显式选择语言后重启，确认偏好恢复；恢复跟随系统后确认后续系统变化仍生效。minimal 默认内存偏好不宣称跨进程持久化。
3. 在三语、窄屏和 200% 字号下检查首页、设置和默认诊断入口，确认无溢出；语言切换不重建 router/session、不丢编辑内容。
4. Android 通知内容与渠道状态的真机自动化已完成，仍需人工核对通知/系统设置的视觉显示；iOS/macOS 在首次请求时核对权限说明。
5. Web 在 Chrome 和 Safari 分别完成完整模板操作。Windows/Linux 在相应主机运行构建与真实 UI 验收。

本地证据保存在忽略目录 `build/localization-validation/`，包含最终完整门禁日志、8 份构建清单、包内资源查询、6 个原生 fixture 结果、真实通知结果及 `runtime-fixtures/` 探针。定向测试的 `result.json` 位于 `build/test-runs/`。运行探针只进入隔离验收工程，没有进入生产模板。

Android 两个测试包已核实不存在，临时电池豁免也不存在；卸载命令曾报告失败，但进一步查询确认测试框架已移除包。专用 iOS 模拟器已关闭并删除，未使用已连接的个人 iPhone。没有以历史设备测试或其他平台结果替代本轮未执行项。
