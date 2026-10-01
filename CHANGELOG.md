# Changelog

## Unreleased
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
