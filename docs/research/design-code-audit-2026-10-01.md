# DESIGN.md 全仓代码审核

本文记录修正前的审核基线；后续实施与验收见[整体修正交付记录](../validation/2026-10-01-design-corrections/README.md)。

日期：2026-10-01。源码基线：`511db2332c91e8de41ef8e4d7cae81f4c686ee31`。

## 结论

**未完整符合 DESIGN.md，不能把当前模板作为已经完成设计验收的企业级 UI 基线。** 主题、工作台外壳和资源拥有者已有可复用基础；主要缺口在页面配方、状态呈现与跨页面回归。用户指出的左右侧栏标题位置不一致是实现偏差，不是有记录的产品设计选择，也不是字体主题没有生效。

本次记录 12 项：1 项 P1、8 项 P2、3 项 P3。P1 表示影响操作可达性的共享组件问题；P2 表示明确功能/配方偏差或影响模板一致性的问题；P3 表示规格与文档收敛。这里只审核本地工程，不涉及发布审核。

## 范围与证据边界

- 全仓已跟踪手写 Dart/Python/Swift/YAML 文件建立清单，共 246 文件，其中实现 175、测试 71；排除生成 `.g.dart/.freezed.dart`、历史研究/验收快照与构建产物。
- 静态扫描覆盖所有上述文件；设计审核重点覆盖 54 个直接导入 Material 的实现文件：koi_ui、Admin、starter、workbench、UI Lab、feature_lab、minimal_module、module_showcase 及其 alpha/beta。
- 补查平台适配生成代码 `tool/platform_configuration.py`、模板复制入口、主题入口、workspace bootstrap/router/会话拥有者与相关测试。domain/data 没有布局职责，不把业务字段审查冒充视觉验收。
- 两个临时 Widget 探针运行真实共享组件/侧栏，存储与播放器使用现有测试替身。探针确认标题坐标、侧栏滚动与错误组件溢出；不证明真实磁盘、原生播放或平台读屏。
- 只新增本报告与证据；未调整生产实现、DESIGN.md 或正式测试。临时探针源码以 `.dart.txt` 保存，执行文件已移除。

证据：[源码清单](evidence/2026-10-01-design-code-audit/source-inventory.json)、[探针源码](evidence/2026-10-01-design-code-audit/widget-probes.dart.txt)、[探针输出](evidence/2026-10-01-design-code-audit/widget-probes.log)、[架构检查](evidence/2026-10-01-design-code-audit/architecture.log)、[AI 资产检查](evidence/2026-10-01-design-code-audit/ai-assets.log)。清单记录每个文件的 SHA-256、行数与设计敏感行号，方便后续修复对照。

## 问题清单

### F05 · P1 · 共享错误状态在大字号和短窗口下溢出

- 契约：DESIGN §5/§8/§10 要求 200% 文字、窄容器与可达操作，不能依赖固定高度挤压。
- 位置：[koi_error_state.dart:20](../../packages/koi_ui/lib/widgets/koi_error_state.dart#L20)；相同结构见 `koi_empty_state.dart:19`、`koi_loading_state.dart`。后两者仅确认结构风险，未在本轮逐一运行溢出探针。
- 触发：320×300 可用区域、200% 字号、正常中文初始化错误文案及重试按钮。
- 复现：真实 `KoiErrorState` 报 `A RenderFlex overflowed by 160 pixels on the bottom`。无滚动容器，不能保证重试完整显示及可达。
- 建议：用标准约束布局与滚动组合，在空间充足时保持居中，空间不足时允许滚动；不能简单缩小字号。统一处理 empty/error/loading，宿主避免重复滚动。
- 回归：320 宽 × 短高度、大字号、长错误文案，滚到重试并激活；另覆盖正常窗口保持居中。

### F01 · P2 · 三个侧栏标题几何不一致

- 契约：DESIGN §6（137 行起）与当前用户要求的统一页面配方。
- 位置：[workspace_panels.dart:34](../../examples/workbench_app/lib/features/workspace/presentation/widgets/workspace_panels.dart#L34)、`:115`、`:173`。
- 字体都正确使用 `titleMedium`；文本标题容器 L12/T20，媒体 L12/T12，任务 L16/T16。探针实际坐标分别 `(12,20)`、`(12,12)`、`(16,16)`。
- 影响：导航切换时标题跳动，任务不满足侧栏水平 12 的共同边界；ThemeData 不会自动统一外层 Padding。
- 建议：共享面板头部组合与空间参数，页面仅传标题/搜索/内容。文档已有水平 12，但**没有统一规定所有面板的顶部数值**；先确定统一顶部值，再写入规范与测试，不能宣称文档已经要求全部 T20。
- 回归：同一壳中切换三视图，测标题起点、搜索与列表选中容器边界，两种密度与 200% 字号都覆盖。

### F02 · P2 · 侧栏固定头部配方没有推广到三个视图

- 位置：`workspace_panels.dart:31` 的文本是 Column + 固定标题/搜索 + Expanded 列表；`:115` 媒体和 `:173` 任务将标题及内容放进同一个 ListView。
- 触发：侧栏高度不足或文字放大后滚动。文本头部保持，媒体/任务头部会随列表消失。
- 性质：文档“资料侧栏”明确固定头部，媒体/任务没有独立例外条款；是跨视图配方缺口，不能把文本实现当作全部视图完成。任务不必添加没有用途的搜索框。
- 建议：统一固定标题和可选搜索的结构，余下区域滚动；媒体说明文字进入滚动内容，保留合理小高度降级策略。
- 回归：长中文、短面板和搜索焦点下滚动，固定头部不被内容推走且不产生溢出。

### F03 · P2 · 素材详情缺少统一属性层级

- 契约：DESIGN §6 详情面板：标题14/20、属性名12/18、属性值14/20、组间距12。
- 位置：`workspace_panels.dart:209–230` 资料详情复用 KoiPropertyRow；`:246–264` 素材详情直接堆 Text，缺少名称/大小/类型/缩略图状态标签；两种详情顶部和标题后间距也不同。
- 影响：资料和素材在右侧没有一致的视觉与阅读结构，多个值无法清楚对应字段；不是有记录的特殊设计。
- 建议：复用 `KoiPropertyRow` 与统一详情头部；错误/重试保留专用状态及操作，不把所有信息降为普通属性。
- 回归：中文长名称、路径、缩略图失败/重试以及空选择，对齐和字段层级一致。

### F04 · P2 · 资料侧栏切换视图后丢失滚动位置

- 契约：DESIGN §8：导航/resize 保持草稿、选择、滚动与稳定会话。
- 位置：`workspace_panels.dart:55`；`workspace_shell.dart:118` 同一个侧栏按 currentIndex 替换内部树，列表没有稳定 PageStorageKey 或会话持有的滚动控制器。
- 复现：真实 WorkspaceSidebar，100 条资料，滚到480px，切换媒体→任务→文本，回到0px。
- 影响：业务会话与主内容分支稳定，不代表外侧列表的局部 Widget 状态稳定。已选资料仍保留，但用户要重新找到浏览位置。
- 建议：每个侧栏独立稳定存储标识或宿主持有控制器；明确 drawer 与内联面板切换共用恢复策略。不要改 router 或媒体拥有者解决这个局部问题。
- 回归：长列表跨视图与跨断点返回，保存滚动及选择；区分正常搜索结果变化需要调整位置的情况。

### F06 · P2 · 文档状态区没有完整表达保存中

- 契约：DESIGN §6（141/149 行）保存中、失败可见，当前文档有状态区。
- 位置：`text_page.dart:191–193` 和 `workspace_panels.dart:224–228` 仅依据 dirty 显示“未保存/已保存”；`workspace_shell.dart:217` 的全局保存指示仅在没有原生工具栏时显示。
- 触发：macOS 已接管工具栏、工作区提交尚未完成。原生桥没有 saving 参数；页面状态也不读取 saving。
- 影响：缺少进行中的反馈。**失败不是完全静默**：shell 有 MaterialBanner 与重试；本项不指控写入失败被吞掉或错误数据覆盖。
- 建议：统一保存展示状态；当前文档状态区表达保存中/未保存/已保存/失败。工作区级 saving 不应错误宣称每份文档已提交，沿用对应 revision 的成功清理语义。
- 回归：延迟保存、保存期间编辑、写入失败、原生/Flutter 工具栏两条路径。

### F07 · P2 · Admin 导航仍采用旧的全窗口二段布局

- 契约：DESIGN §8 局部可用宽度、600/1024 断点及桌面导航组织。
- 位置：[home_shell_scaffold.dart:18](../../apps/koi_admin_app/lib/features/home/presentation/widgets/home_shell_scaffold.dart#L18)：全局 MediaQuery + 960；设置与总览并列普通 destination；桌面保留整高 VerticalDivider，主体没有工作台表面组织。
- 触发：600–959 可用宽度仍显示底部栏；嵌入窄容器时按窗口宽度做错误选择。
- 建议：用 LayoutBuilder 采用约定断点与共享导航组合。Admin 可以保持简单两页，但需要明确并测试其有效例外；不能只接 AppTheme 就宣称全部外壳统一。设置页面也需限制宽窗口表单/信息跨度（settings_page.dart:19）。
- 回归：窗口与局部容器宽度不同、600/1024 边界、短窗口底部设置可达。

### F08 · P2 · Admin 的登录与初始化失败绕过完整主题体系

- 契约：DESIGN §2/§3/§4 中性表面、明暗主题与统一字体角色。
- 位置：[login_page.dart:61](../../apps/koi_admin_app/lib/features/auth/presentation/screens/login_page.dart#L61)：硬编码浅色渐变；[bootstrap_failure_app.dart:11](../../apps/koi_admin_app/lib/core/bootstrap/bootstrap_failure_app.dart#L11)：MaterialApp 无 AppTheme/darkTheme，标题 Theme.of(context) 读取的是其新 MaterialApp 之外的上下文。
- 影响：Admin 正常入口接主题，异常入口却退回 Flutter 默认样式；暗色登录保留大块浅色背景，与工作台和最小模板不一致。
- 建议：异常入口用共享主题和反馈配方；登录表面从主题取色，有特殊品牌背景时记录明暗配对例外，并保留对比度验证。
- 回归：系统明暗、初始化失败、长 debug 错误、键盘与大字号登录。

### F09 · P2 · 次要 tonal 按钮仍使用 seed 生成的有色容器

- 契约：DESIGN §4/§12：次要操作中性、主要操作品牌色。
- 位置：`koi_material_theme.dart:130` FilledButtonTheme 仅统一尺寸/焦点，没有覆盖 tonal 容器前背景；`app_theme.dart:21` 的 seeded ColorScheme 保留 secondaryContainer；`ui_lab/standard_component_catalog.dart:117` 将 FilledButton.tonal 标为“次要操作”。
- 证据：固定 SDK Flutter 3.47.2 的 `filled_button.dart` 中 tonal 默认颜色来自 secondaryContainer，主题未覆盖该属性。不是所有按钮缺主题，而是此变体没有跟随中性规则。
- 建议：决定 tonal 是否是明确的有色例外；若按当前文档保持中性，优先通过 ColorScheme/主题映射调整，测试正常/禁用/焦点前背景配对，不重写按钮。
- 回归：四种主题/密度组合中主要与次要的强调层级，保留焦点和禁用可辨识度。

### F10 · P3 · 导航/触摸图标尺寸与规格不一致

- 契约：DESIGN §5/§7：导航22，comfortable 工具图标20–24。
- 位置：`koi_material_theme.dart:269–271` rail图标20；`:63` 公共按钮图标固定18，未按密度区分。
- 影响：命中区域主题已单独处理，这里是视觉规格偏差，不等同于触摸目标不足。
- 建议：集中图标尺寸角色，决定保留20的明确例外或落实22；让comfortable与compact的视觉值按文档一致，避免页面逐个覆盖。

### F11 · P3 · 搜索配方声明有清除按钮，实际没有

- 契约：DESIGN §12 标准组件映射的“带清除按钮”。
- 位置：`koi_search_field.dart:17–28` 只有 TextFormField.initialValue 和搜索prefix，无suffix清除入口或受控 controller API。
- 影响：规范与公共 API 不一致；用户必须手动删除，宿主也不能通过现有 API 主动同步清空正在编辑的输入。
- 建议：按真实需求补轻量标准输入组合及语义清除按钮，明确外部值同步契约；或先修正能力声明，不能只改 UI Lab 伪造支持。

### F12 · P3 · 文档和验收机制没有约束真实跨页面配方

- 位置：DESIGN §10 声称“侧栏已统一”，§12 声称清除按钮；UI Lab 使用独立样例内容，没有直接覆盖真实 WorkspaceSidebar/WorkspaceDetails 三视图几何。
- 现状：现有测试覆盖许多功能、焦点、菜单与触摸目标，但本轮没有发现对三个侧栏/两个详情的共同标题边界、固定头部和往返滚动的比较断言。
- 影响：架构检查和高覆盖率仍可通过，用户看到的错位却继续进入新项目。
- 建议：精确修订已完成声明和例外；共享配方同时受 UI Lab 与工作台消费；增加少量真实面板几何、状态保留与可达性回归，随后补视觉矩阵。不要用扩大覆盖率排除目录代替验收。

## 已符合或有合理边界的部分

| 领域 | 代码结论 | 范围/保留意见 |
| --- | --- | --- |
| 字体角色 | AppTheme 定义了标题/正文/辅助角色；侧栏标题确实都用 titleMedium | 不能统一 Padding；特殊页面未全面收敛，见F08 |
| 壳/侧栏/正文分色 | KoiWorkbenchFrame 用 chrome/panel/content 独立语义表面，内容有真实圆角裁切 | 属性和标题几何仍属页面责任；本轮不声称各平台最终像素一致 |
| 自适应工作台 | 局部 LayoutBuilder、600/1024区间、rail/抽屉/内联面板 | Admin仍为旧实现；列表恢复见F04 |
| 密度 | token有明确密度；行高/控件高度/分隔拖拽目标分别处理 | 图标规格见F10，不把宽度等同鼠标 |
| 基础组件职责 | koi_ui 未依赖 Riverpod/go_router/业务 repository | 展示壳与纯组件边界正确，无需新建业务模块解决视觉差异 |
| 状态拥有者 | bootstrap持有同一个router/session/preview，typed shell持有分支，文本控制器有稳定归属 | 外侧栏滚动并未随之稳定 |
| 菜单/浮层 | 实现有关闭/焦点/语义与清理机制，已有专项测试 | 本轮没有重新执行全部键盘、Back、读屏与真机矩阵 |
| 原生标题栏 | 生成的AppKit配置透明统一标题栏、两个独立无边框按钮、面板图标、主题标题规格传递 | 没必要再调整返回按钮背景；保存反馈见F06 |
| 待办与IO作业 | 不同模型；确认删除包含具体名称、取消默认焦点；进度/失败/重试有真实状态 | 无需为了统一侧栏改变任务执行语义 |
| 简单模板/模块样例 | 入口接AppTheme；library/模块页面由宿主提供主题 | 不要求每个简单页面强行加入工作台四栏；不是例外遗漏 |
| 生成链路 | blueprint.py:358–380复制模板和共享包；:389复制DESIGN | workbench新项目会继承F01–F06，不能只修运行中的生成产物 |

## 规范本身需要补足的约束

1. 公共面板标题顶部、标题后间距、搜索区上下间距目前未形成完整数值契约；水平12已明确。不能要求实现遵守未写出的顶部值。
2. 区分“全局图标导航”与“内容内的资料/筛选侧栏”；这两个区域不能因为名称都有侧栏而共享背景角色。现有 tokens 能表达，继续保留。
3. 明确所有同级内容侧栏采用固定头部/可滚动主体，或逐项说明例外；给详情也定义共同头部组合。
4. 规定保存状态的展示映射、滚动恢复拥有者，以及辅助有色组件的有效例外。
5. “企业级”通过复用、可达状态、失败恢复与回归矩阵证明，不靠新增组件数量或复制一个客户端的配色证明。

## 推荐修复顺序

1. **可达性和状态**：F05、F04、F06；先保证重试可用、导航不丢浏览位置、提交过程可理解。
2. **页面配方**：F01–F03；ThemeData保留标准控件，koi_ui新增或完善薄的面板头部/主体组合，接入三视图与两个详情，复用KoiPropertyRow。不要新造导航引擎或按钮。
3. **入口与标准主题**：F07–F09；Admin、异常入口及tonal一起落实规范，保持简单模板边界。
4. **规格与门禁**：F10–F12；同步DESIGN、UI Lab、真实消费测试和生成源，再执行完整validate与fresh-project验证。

修复后应验证320/600/1024/1440、明暗、两种密度、100%/200%字号，以及面板隐藏/恢复。针对F04加resize/抽屉往返；针对F06加延迟/失败提交。真实macOS/Windows/Linux/Android/iOS/Web运行、Chrome/Safari与读屏验证另行记录，不用Widget替身替代。

## 本轮执行结果

| 项目 | 结果 |
| --- | --- |
| 工作区基线 | 审核前clean，main基于511db23；本轮仅新增报告/证据 |
| `python3 blueprint.py check architecture` | PASS，16成员 |
| `python3 blueprint.py check ai` | PASS |
| 临时Widget审计探针 | 2项PASS：**期望捕获已存在的偏差**，不是设计验收通过 |
| 标题/侧栏状态证据 | 坐标12,20 /12,12 /16,16；滚动480→0 |
| 错误组件证据 | 320×300、200%字号、底部溢出160 |
| 完整validate/覆盖率 | 本轮NOT_RUN；审计未改生产实现，不复用上一轮结果冒充新验收 |
| fresh-project/六端构建运行/浏览器视觉矩阵 | 本轮NOT_RUN |
| 修复 | NOT_IMPLEMENTED：本轮请求为全代码审核 |

探针重跑：将证据 `.dart.txt` 临时复制到 `examples/workbench_app/test/design_audit_probe_test.dart`，在仓库根运行 `./tool/flutterw test examples/workbench_app/test/design_audit_probe_test.dart --reporter expanded`，执行后移除临时文件。修复完成后应把探针的“偏差存在”断言改成符合契约的正式回归断言，而不是长期保留反向验收。
