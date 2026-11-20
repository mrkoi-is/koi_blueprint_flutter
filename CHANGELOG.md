# Changelog

## Unreleased

## 0.3.2

- Chrome 定向测试从独立的 Flutter JSON 报告读取用例证据，控制台日志单独归档，修复 Flutter 3.50.1 下持久化用例误报证据不完整。
- `generate-check`、创建工程、安装能力和完整验证现在都按 Pub 解析的 workspace 依赖顺序运行 `build_runner`。安装能力时，临时工作区和实际工程都会先生成依赖包，再生成使用它们的 App。
- 安装能力时，若新依赖包已生成而 App 生成失败，回滚会清理本次新包的 SDK 缓存和匹配的生成文件，允许重新安装。用户另加或改写的源文件会保留。
- 能力安装按 key 合并 ARB，保留项目自定义译文并补入配方新增文案。同版本重装支持刷新译文，双方对同一 key 的不同修改会报告文件和 key。
- 将蓝图、生成工程和 CI 的 SDK 升级至 Flutter 3.50.1 / Dart 3.14.0，更新 workspace SDK 约束和锁文件。新建 Android runner 使用 AGP 9.3.2，修复 JDK 17 下的 release lint 崩溃。
- 修复 App 目录名与 Dart 包名不一致时的升级误报。`upgrade-report` 和 `upgrade plan` 共用 App 的 `pubspec.yaml` 包名，已采用的导入修复可正确归类为 `alreadyApplied`，计划也会用该包名还原基线并生成新的导入。

升级步骤与验证范围见[版本记录](docs/releases/v0.3.2.md)。

## 0.3.1

源码补丁版，合入 `54716bd` 的升级事务与诊断资源清理修复。完整范围见 [补丁记录](docs/releases/v0.3.1.md)，发布后的固定提交、CI、产物及日期见 [GitHub Release](https://github.com/mrkoi-is/koi_blueprint_flutter/releases/tag/v0.3.1)。

- 升级计划不生成受审工程的 Python 缓存，输出位置必须位于目标 workspace 与源蓝图之外；在调用 pub 前拒绝不明确的依赖 YAML 与越界本地路径。
- 新增工具继承上游执行权限，已有文件保留本地权限；备份和回退恢复前再次校验内容，拒绝并发修改或损坏备份。可选能力包的源码变更仍需人工迁移。
- LAN 重复停止共享同一清理任务，停止期间禁止重启，订阅取消使用稳定快照；Android 前台服务停止失败后保留所有权，允许后续清理重试。
- macOS CI 媒体能力摘要使用 runner 自带的 grep；同步 README、升级指南、工具说明与默认诊断能力说明。


## 0.3.0 — 2026-11-17

源码正式版，将已发布的诊断、国际化、测试与升级工具整合至 main。完整范围、迁移边界和未执行场景见 [版本记录](docs/releases/v0.3.0.md)，最终提交、CI 与产物摘要见 [GitHub Release](https://github.com/mrkoi-is/koi_blueprint_flutter/releases/tag/v0.3.0)。

- 默认 diagnostics v2：Talker 日志与网络记录、设备内查看、持久化与导出、临时授权的局域网查看；包含 Android release 后台诊断接线及已发布的 SSE、轮转和流式响应修复。
- 整合 ARB 驱动的英／简／繁语言策略、Apple 本地化资源、Android 通知渠道与 LAN 网页翻译，保留 Windows CRLF 兼容修复。
- 整合定向测试、Golden、持久化验收与受管升级事务；历史工程的依赖冲突仍需人工迁移。
- 同步 README、创建指南及初始化契约中的默认诊断、显式能力选择和 Chrome 前置条件；补齐候选发布证据，区分历史设备验收与最终提交构建。
- 本版发布从合并后的 main 提交构建并归档；验证应用不代表正式签名的业务 APK，六端完整国际化 UI 验收仍未完成。

## 0.3.0-rc.1 — 2026-11-17

已发布的源码预发布，整合测试工具与诊断修复。发布提交 `046850e` 的 CI 为 19 项成功、1 项不适用跳过，两模板六端共 12 个构建组合通过。已验证范围和未执行项见 [版本记录](docs/releases/v0.3.0-rc.1.md) 与 [GitHub Release](https://github.com/mrkoi-is/koi_blueprint_flutter/releases/tag/v0.3.0-rc.1)，不代表六端完整国际化 UI 验收。

- 合入主分支 analyzer 14.5.0、build_runner 2.16.2 与 CI checkout 更新。旧项目因依赖差异需人工审阅迁移；CI 明确验证拒绝应用且工程保持不变，不将其记为自动升级通过。
- 修复 macOS 监督进程在清理僵尸进程组时丢失超时报告的问题；只有确认进程组不存在活成员时才接受清理完成。
- 补齐新建 minimal/workbench 的 iOS/macOS 英／简／繁语言声明，并将诊断局域网权限译文作为 `InfoPlist.strings` 资源打包；后装诊断能力同样接入，重复安装保持幂等并保护已有用户修改。
- 修复 Windows 宿主创建六端工程时 Apple 本地化解析不接受 CRLF 换行的问题；保留工程原有换行格式，并覆盖两阶段安装与重入。
- 原生语言资源校验兼容 CocoaPods/Xcode 的工程重排；构建准备阶段仅对仍匹配基线的原生文件同步 SDK 迁移后的记录，避免后续能力安装误报冲突，不吸收构建前的用户修改。
- 诊断 Android 通知、LAN 网页标题和导出失败提示支持三语；通知渠道改名保留原渠道及用户设置；网页 `lang` 使用实际译文的 BCP 47 标签，兼容旧下划线标签及中文脚本／地区偏好。新增原生资源生成、通知调用和 Chrome 网页行为回归。
- 保留合并前国际化修复阶段的两模板四平台构建、macOS/Android/iOS 模拟器三语引擎测试及 Android 真机通知证据。发布提交的六端构建结果单独记录；Windows/Linux 国际化 UI、Safari 和系统权限弹窗仍待验收，见 [国际化验收记录](docs/localization-validation.md)。
- 修复已有工程的平台 CI：在各自作业内准备依赖并重新生成 Dart 代码，避免干净检出缺少 Riverpod、路由与模型生成文件。
- 修复调试会话监控或状态写入失败后的进程回收，隔离命令进程组并保留已观察进程的身份校验，避免遗留子进程或误杀无关进程。
- 修复 Dio 流式响应的诊断状态与耗时：根据正文流完成、错误或取消结束记录，保留原始字节、异常及暂停／恢复行为；补充对应回归测试。
- 统一 App 国际化配置到 `appLocalePolicy`：支持语言由 ARB 生成结果驱动，语言选择器、偏好恢复和回退策略共用配置；兼容旧的下划线语言标签，未知或已移除的语言偏好恢复为跟随系统。
- 修正中文语言匹配，显式 Hans/Hant 脚本优先于地区推断；补齐共享组件、启动加载／失败页及独立样例入口的国际化配置。
- 新增 `python3 blueprint.py check l10n`，检查 ARB 翻译键完整性、空译文、重复 JSON 键、locale 与占位符元数据，并接入生成、创建项目和能力安装流程；完整 ICU 语法继续由 Flutter `gen-l10n` 验证。
- 补充参数化文案的翻译说明、语言切换与旧偏好恢复回归，以及英／简／繁在 320px 窄屏和 200% 字号下的交互测试；使用约定见 [国际化契约](docs/architecture/localization.md)。

## 0.3.0-android-rc.1

- 新建 minimal/workbench 项目默认安装 diagnostics v2，使用 Talker 统一采集日志与已接入客户端的网络请求。
- 增加 release 隐藏诊断入口、20 MiB 持久历史、脱敏、流式请求状态/耗时、查询与 NDJSON 导出。
- 增加带会话凭证的 LAN 实时查看器及 Android 前台保活；修复超长日志布局，保留 Web 的只读本地诊断。
- 修复慢速磁盘突发写入的分段轮转，修复 SSE 首帧期间可能漏失实时更新的竞态，覆盖活跃连接的关闭与端口释放。
- 生成器烟测为默认诊断使用真实 Chrome，并单独验证显式空 capabilities 的无浏览器路径；Windows 浏览器 SDK 兼容补丁覆盖两种模板。
- 发布范围为 Android RC；APK 使用测试签名，不代表正式商店签名或六端实机认证。设备验收与发布索引见 [Android RC 记录](docs/releases/v0.3.0-android-rc.1.md)。

## 0.2.0 — 2026-11-17

已发布版本的最终验收与边界见 [GitHub Release](https://github.com/mrkoi-is/koi_blueprint_flutter/releases/tag/v0.2.0)。

- 新增基于 Flutter 测试框架的定向测试 CLI：按活动成员和显式文件运行 VM 或 Chrome 测试，输出范围、实际执行结果、原始事件、源码指纹与哈希；定向通过不替代完整门禁。
- 为测试、覆盖率、浏览器与完整验证引入 workspace 进程锁和异常诊断；结果原子发布，超时、源码变化、锁冲突及证据缺失不记为通过。
- 新增固定字体的 macOS ARM64 Golden 和跨版本基线选择；macOS 26 与 27 各使用已审阅的图片、零像素容差，其他 macOS ARM64 版本需先审阅；不支持环境的跳过不构成通过。
- 增加 Workbench 真实 UI 与 Native/Web 持久化行为测试，覆盖保存重开、保存中编辑、失败恢复和单写者；桌面跨进程写读单独保留证据。Linux 原生媒体冒烟增加有界进程和 reporter 完整性检查。
- 扩展生成项目的 AI 测试入口与 CI 证据：按源仓、minimal 和 Workbench 选择成员；校验用例数量、事件和哈希；固定旧版基线执行升级矩阵并保留失败产物。
- 在只读升级报告之外提供 schema 2 受管升级计划、事务应用与回退；无法证明来源、未解决的冲突和不受支持的依赖变更会阻断，数据格式不会由工具自动迁移。
- 增加使用预构建 macOS App 的 POSIX AI 会话管理入口，保留会话与进程诊断；Dart MCP 的保存读回需要实际连接及状态断言，Windows 会话管理和 Chrome 热重启尚不支持。
- 自候选版以来强化 ARCH014 异步状态生命周期检查，修正 Windows SDK、UTF-8、路径与覆盖率兼容，并完善桌面媒体、浏览器选择器及 CI 的原生媒体诊断。


## 0.2.0-rc.1 — 2026-10-04

本版本为 Web/macOS 验收范围的本地候选版。其他平台、浏览器与人工理解反馈分别记录，不能由候选 tag 推导为六端稳定版。验收范围见 [候选版本记录](docs/releases/v0.2.0-rc.1.md)。

- 完整启用 Riverpod lint，补齐作用域依赖和消费元数据；统一样例的状态拥有者、错误重试、迟到结果隔离及资源释放。
- 修复 Workbench 保存队列交错失败时的引用补偿、Draft 子会话隔离与真实路由返回、原生退出监听器及保存等待；补永久行为回归。
- 整理当前未提交源码与测试，构建缓存符号链接作为本地派生产物排除，保留原链接与目标。
- 技能正文收敛到 `.agents/skills`，删除 `.agent` 与发现适配副本。升级报告不改文件；仍保持基线的 `.agent/**` 会显示上游消失，`.agents/skills/**` 会显示为完整正文，需手工删除旧目录并采用新正文
- 工作台加入 Native 文件锁与 Web Locks 单写者保护、可取消退出协议及真实进程/浏览器锁回归
- 新增 run/devices/doctor 子命令和模板继承资产门禁，生成项目使用可发现的启动与平台验收入口
- 修复兼容 Feature 入口覆盖显式 kind、minimal 的 Chrome 过度门禁；生成 README 从 .fvmrc 读取 SDK 版本
- 补齐 CLI 参数语义、分项 Make 入口、成员 README 与工具清单；Skill 维护/平台验收/Melos 文档可发现性进入 AI 门禁
- 归档 2026-09-30 整改方案并关联后续验收证据，更新 AGENTS 的 UI 路由与完整验证范围
- 新项目默认接入 koi_ui；新增 minimal/workbench 模板、确定性平台配置和两种模板的六端构建矩阵
- 增加产品主题 token、两种密度、自适应工作台组件与 UI Lab；Admin、starter、module showcase 统一主题
- 增加文本、素材、待办及真实任务工作台，Native 备份快照与 Web IndexedDB/Blob 持久化、真实媒体预览和缩略图
- 浏览器行为进入 validate，未采集浏览器行以零命中纳入覆盖率；增加真实播放器集成 fixture 与 CI 运行证据保留
- 修复目录初次加载与刷新竞态、草稿输入框外部同步、模块含 query/fragment 的冷启动深链，并加入迟到结果与资源销毁回归
- 补强 AI 围栏链接、发现入口同步和 ARCH007 的形参、级联、遮蔽检查；研究与历史验证材料不再进入生成项目
- 明确 Python 3.11 下限及 Flutter/Dart SDK 选择顺序，生成项目独立初始化身份与变更记录，增加递归创建与双 Python 版本验收
- 记录 2026-09-30 的源码、真实生成项目和 macOS 宿主 Web/Android/macOS/iOS 构建结果；Linux/Windows 待对应宿主验证
- 建立统一 Python 脚手架与按平台验证入口，最小生成项目不附带认证/网络示例依赖
- 完善 9 个 canonical Skills、Codex/Claude/Cursor 入口、按需 references 与维护契约
- 加入最小宿主、三类 Feature 与模块组合样例，文档引用集中到可迁移的样例地图
- 明确 data/application 可共存、展示 props、Riverpod 3 异步错误和资源生命周期
- 增加 AI 资产/架构检查和生成回归范围，将手写覆盖率门槛提升到 80%
- 补充贡献指南、Issue/PR 模板和可追溯设计参考
- 补齐 Web 可运行脚手架，并将工具链升级至 Flutter 3.47.2 / Dart 3.13.2
- 将 Melos 升级至 8.9，并统一 Riverpod 3.4.3 / Freezed 4.0.2 / analyzer 14 的代码生成依赖
- 统一 pub.dev 锁文件来源与本地、CI 完整验证入口
- 修复白名单与异常消息造成的 401 会话处理错误、窄屏卡片溢出和 Feature 脚手架路径校验
- 将仅首页使用的展示模型移回 Feature，脚手架支持仅生成展示层
- 补启动装配到演示登录的回归测试，并将未实现的主动 token 刷新默认关闭
- 修复认证会话、GoRouter 生命周期、路由循环依赖与启动异常边界
- 将 token 改为内存会话并接通 `koi_network` 认证与 401 回调
- 新增 Native/Web 条件网络后端、CI、生成物检查和 60% 覆盖率门禁
- 认证写入与登出串行化，401 按请求 token + session revision 隔离旧会话，并让存储失败保持 fail-closed
- 覆盖率门禁补查未加载的可执行源码
- 生成物（`*.g.dart` / `*.freezed.dart`）改为不入库，本地与 CI 通过 `generate` 重新生成
- 将 Workspace 测试扩展到全部 6 个成员

## 0.1.0
- 初始化 `koi_blueprint_flutter` Monorepo 蓝图
- 建立 `apps + packages + docs + AI assets` 基础骨架
- 提供 Riverpod 3 + go_router + Freezed + workspace + Melos 基线
