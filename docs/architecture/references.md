# 架构参考与取舍

核对日期：2026-09-29。以下来源用于设计比较，不作为使用蓝图的前置依赖。蓝图自身的契约、样例和测试负责说明实际采用的行为。

## 公开一手资料

| 来源 | 借鉴内容 | 本蓝图的取舍 |
| --- | --- | --- |
| [Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations) | UI/数据职责分离、仓库、依赖注入、可替换测试与按复杂度引入领域层 | 保留职责分离，使用 Riverpod 实现状态/注入；不把建议的具体状态库或完整 UseCase 层作为每页硬要求 |
| [Flutter Compass 源码入口](https://github.com/flutter/samples/tree/main/compass_app) | 官方架构建议提供的完整应用参照 | 借鉴真实纵向样例的组织方式，不照搬旅行领域或认证需求 |
| [Very Good CLI](https://github.com/VeryGoodOpenSource/very_good_cli) | 带名称/组织/平台输入的创建命令、可复用模板、递归测试和覆盖率参数 | 使用本仓库 Python 入口统一已有工具，不额外要求全局安装另一套 CLI |
| [Mason](https://github.com/felangel/mason) | 可重复消费的参数化模板 | 保持脚手架与受测源码一致；现阶段不增加第二种模板运行时 |
| [Riverpod 自动销毁](https://riverpod.dev/docs/concepts2/auto_dispose) | 自动销毁、keepAlive 与资源清理 | 显式选择页面/会话/应用生命周期，不能把 provider 当作永久存储 |
| [Riverpod select](https://riverpod.dev/docs/how_to/select) | 缩小订阅值与重建范围 | 先确保不可变状态与 equality，再依据测量优化；family 本身不保证单条重建 |
| [Codex Skills](https://developers.openai.com/codex/skills) | 原生 Skill 发现与按需加载 | 技能正文直接放在 `.agents/skills`，与原生发现目录一致 |
| [Claude 项目指令](https://code.claude.com/docs/en/memory) | 项目记忆/指令文件及导入机制 | CLAUDE.md 只导入统一入口；客户端能力须在实际环境验证 |

这些是具体机制的参考，不是按 star 数或流行度给项目排名。版本和客户端行为变化后，应重新核对相关接口并执行回归。

## 个人项目的实证经验

这次只读审查抽样了 JieJing 新 Monorepo、Learning Officer OA 和 Live Wallpaper Studio 的当前文件。以下记录经验来源，不要求读者访问这些本地/私有项目。

| 项目经验 | 已观察到的实现 | 继承到蓝图的机制 |
| --- | --- | --- |
| JieJing | apps/packages、注解式 Riverpod、类型化路由、repository、按任务触发定制 Skill | 保留技术路线和依赖方向，不带入物流、支付、Drift 或旧版依赖 |
| Learning Officer OA | 短 Skill + references；页面创建区分路由/首页；参数、注册与验证清单；运行时装配对应真实代码 | 补齐任务执行契约；把 GetX Binding 的生命周期意图改为 provider/session/宿主装配 |
| OA 治理的反例 | Skill 审计只检查格式/标题/长度；迁移文档后仍有失效链接 | 增加引用完整性、模板生成和行为测试，不以“10 分”样式评分证明可执行性 |
| Live Wallpaper Studio | 共享端口与组合根、数据实现复用、架构边界检查、只减不增的例外清单、产品差异表 | 允许本地 IO 与应用编排共存，记录资源拥有者和有效例外，不复制媒体格式与平台领域规则 |

## 固定的设计结论

1. 架构不变量与产品依赖分开：账号、网络、数据库、原生引擎按需加入。
2. 新项目默认选型与存量迁移例外分开：现存成熟状态机可通过边界适配，不为形式统一重写。
3. 规范必须能走到真实装配点：生成文件、注册路由、注入实现、测试生命周期缺一不可。
4. UI 展示参数合法；业务容器和纯展示组件承担不同职责。
5. 文档链接、Skill 描述、生成模板与运行检查组成同一维护范围。
6. 下游项目完全自包含，不依赖作者目录、其他业务仓库或个人 Skill。

新增取舍记录应说明问题、采用方式、未采用内容和验证证据；不要只添加新的绝对禁止项。
