# 桌面设计规范与第一轮实施验收

日期：2026-09-30。对应 [DESIGN.md](../../../../DESIGN.md) 与 [源码/截图对照报告](../../desktop-ui-design-comparison-2026-09-30.md)。这是本轮结果，未沿用此前验收值。

## 修改完成

- `koi_ui` 集中字体角色、中性明暗表面、选中/hover/overlay、独立密度与圆角；普通 Material 宿主保留回退。
- 共享列表保留弱选中与独立焦点环；新增 SearchField、Toolbar、ReadingPane、PropertyRow，继续只接收 Widget、数据和回调。
- 工作台使用单行资料列表、低强调工具栏、最大 800 的透明正文区与详情属性配方；编辑控制器、会话、路由及播放器拥有者继续沿用。
- UI Lab 消费共享规格；macOS 原生标题的字号/字重从主题规格传入，生成的 Swift 使用系统字体。
- 默认 minimal 与 workbench 均复制 DESIGN.md；生成 README 和 AI Quickstart 提供入口；四种模板递归组合的单元测试保留目标项目自定义设计正文。

受影响文件改动前副本见 [baseline.json](baseline.json)；最终改动路径见 [changes.json](changes.json)。用户此前已有修改保留，未提交、推送或重置工作树。

## 本地门禁

| 检查 | 本轮结果 | 证据与范围 |
| --- | --- | --- |
| `python3 blueprint.py validate` | PASS | [完整日志](validate.log)：架构、AI 资产、代码生成、格式、分析、测试与手写覆盖率 |
| 手写 Dart 覆盖率 | 87.66%，3589/4094 | 最后侧栏对齐/Tooltip 调整后重跑；未扩大目录级排除；浏览器桥接按既有真实浏览器/零命中分母规则处理 |
| 生成器、AI 资产、平台配置 Python 测试 | 49 tests PASS | 本轮执行 `scripts.tests.test_blueprint`、`tool.tests.test_ai_assets`、`tool.tests.test_platform_configuration` |
| `koi_ui` | 28 tests PASS | 包含新增 6 个行为测试：明/暗×密度、320 宽/200% 中文、输入与激活、实际控件增高、选中与焦点共存、阅读宽度、普通 Material 回退 |
| 工作台、UI Lab | 72 / 3 tests PASS | 原有会话、导航、文本、媒体拥有者与窗口桥接回归；UI Lab 新增搜索输入使用稳定 key |
| Chrome 真实浏览器门禁 | 8 tests PASS | 实际 IndexedDB/Blob 重开、事务失败与暂存清理、图片解码缩略图、Object URL 释放；这不是 Chrome 页面视觉验收 |
| 四种模板递归组合 | 单元测试 PASS | 使用测试 SDK/生成 fixture；本轮没有重复执行四种完整真实 SDK 递归构建 |
| 默认 minimal 真实生成 | PASS | [生成日志](generated-minimal.log)、[AI 检查](generated-minimal-ai.log)、[manifest](minimal-generation.json)；生成时完整复制 DESIGN；平台为 Web；未在此 fixture 另做构建/运行 |

这些检查没有模拟宣称真实视频播放、首帧截图或六端运行成功。

## 目标平台构建

从当前蓝图真实生成独立 `shell_review` workbench，选择 macOS/Web。原生 runner 来自当前 SDK 与确定性平台配置。

| 平台/模板 | 构建 | 实际运行 |
| --- | --- | --- |
| macOS / workbench | Release PASS | 文字页明/暗、中文资料重开显示、原生历史后退与任务空态已观察 |
| Web / workbench | Release PASS | 本轮页面视觉、播放与 Safari：NOT_RUN；Chrome 存储/图片/URL 门禁另见上表 |
| Android/iOS/Windows/Linux / workbench | NOT_RUN | NOT_RUN |
| minimal 六端 | 真实 Web 生成/AI 检查 PASS；本轮独立平台构建 NOT_RUN | NOT_RUN |

构建证据见 [日志](generated-workbench-build.log) 与 [生成宿主源文件 SHA](after-runtime.json)。固定媒体依赖产生 Swift Package Manager 兼容提示，Web 构建另有字体资源提示；最终日志中的 Wasm dry run 成功。当前 macOS 原生 Release 与 Web JavaScript Release 构建均成功；本轮没有执行 `--wasm` 构建/运行或完整媒体运行验收。

## 截图与操作步骤

1. 改动前 Koi Debug 文字页：保存并检查 [截图](koi-current-light.png)。未命名资料、0 字；大标题、双行列表与巨大表单框支持差距判断。
2. 用户明确提供的 Codex 明色/暗色与 Koi 暗色局部：保存原图并记录 SHA；只作为参考。没有新捕获 Codex 窗口，也没有将打包 CSS 当成官方完整设计规范。
3. 改动后 macOS Release 任务空态：[截图](koi-after-light-tasks.png)。标题栏历史按钮可用；依次点击原生后退，实际从任务→媒体→文字页，前进状态随之更新。没有据空态宣称任务执行通过。
4. 首轮 macOS Release 明色：[截图](koi-after-light-text.png)。逻辑 1710×1007，DPR 2，100% 字号，compact；中文“设计规范.md”、82 字、版本 1、已保存。先重开 App，再使用系统 zoom；截图包含窗口阴影，标题栏未激活。这张图在最后侧栏对齐/Tooltip 微调之前保存。
5. 最终 macOS Release 暗色：[截图](koi-after-dark-text.png)。同一资料与尺寸，包含最后对齐/Tooltip 修改；关闭 App 后仅准备独立 fixture 的持久化主题偏好再重开。此步骤证明实际暗色展示与内容重开，不证明设置菜单操作。
6. 最终 macOS Release 明色中等窗口：[截图](koi-after-light-narrow.png)。逻辑 800×600，DPR 2，100% 字号，compact；同一资料，侧栏/详情按需显示。自动化接口连接窗口超时；只读窗口清单确认唯一测试窗口后按窗口 ID 捕获并检查图像，没有继续操作界面。

步骤 3–6 均打开保存的图片检查，并核对窗口标题、资料/空态、主题与逻辑尺寸。图片来源、SHA、时间与状态见 [截图清单](screenshots.json)。

测试宿主的 `main` 仅用于种入三份中文资料与明确的 compact/主题偏好，Web 使用专属数据库名；Native 使用测试 App 独立 bundle 的应用管理目录。最初指定全局临时目录时被 macOS 沙盒拒绝，随后恢复模板已有的应用管理路径并重新构建，不修改沙盒保护。fixture 的普通重开加载真实快照；主题/选择准备直接修改已关闭 fixture 的测试快照，不能解释为设置菜单或资料编辑的 UI 验收。

最后一次增量构建曾出现嵌套代码签名无效，随后仅清理独立 fixture 的派生产物，重新构建 macOS/Web；最终 `codesign --verify --deep --strict` 成功，且已取得最终实际窗口。该过程记录为本机构建产物问题，没有更改签名检查或系统保护。最终明色窗口已正常显示，但自动化连接超时；完整交互验收仍保留未执行。

本轮自动化能够打开/关闭重命名对话框，但未确认键盘输入生效；设置按钮的坐标操作也未观察到菜单展开。两项保留未验收，完整键盘/触摸/读屏不得据 Widget 测试或截图宣称通过。

## 仍待验收

规范复核统一了三处细节：compact 搜索为内容驱动、100% 字号基线约 32；两种密度的导航图标均为 22；侧栏标题、搜索和列表容器共用 12 的水平边界，长文件名提供悬停提示。新建/导入统一放在主体工具栏，使资料侧栏隐藏时仍可使用。

六端字体与图标的光学差异；全部页面在 320/600/1024/1440 和 100%/200% 的实际视觉矩阵；长路径及错误状态；真实 Tab/Enter/Space/Escape、设置菜单、触摸与读屏；媒体播放/截图/释放及全部真实业务流程；Chrome/Safari 视觉与播放。代码行为门禁和部分实际 macOS 展示已通过，上述项目仍为 NOT_RUN。
