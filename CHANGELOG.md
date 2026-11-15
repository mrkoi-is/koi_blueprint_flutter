# Changelog

## Unreleased

以下变更位于候选版本中，正式发布前仍须完成发布验收。详见 [发布准备记录](docs/releases/v0.2.0.md)。

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
