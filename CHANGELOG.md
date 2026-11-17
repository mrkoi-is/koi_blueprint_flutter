# Changelog

## Unreleased

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
