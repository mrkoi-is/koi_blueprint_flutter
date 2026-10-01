# Koi UI 标准组件覆盖审计

日期：2026-10-01。范围：`packages/koi_ui`、`examples/ui_lab`、`DESIGN.md` 及当前工作台消费者。性质：只读源码审计；未执行新的测试、截图或目标平台运行。行号为审计时工作树，后续实施可能移动。

## 结论

已有 kit 的长处是工作区壳、列表、浮层的生命周期与键盘契约；薄弱处是通用 Material 控件家族覆盖不完整、状态规范没有统一落到全部控件、UI Lab 尚不是组件目录。无需从头自绘按钮、选择器、表格或对话框。扩展 `AppTheme` 并为标准控件提供真实交互样例，最符合本次“Theme 优先、缺少再建组件”的要求。

没有显式组件主题不等于组件不可用：这些控件现在仍正常继承 Flutter Material 默认行为和 ColorScheme。应把问题称为“缺少 Koi 的一致外观/密度/验收契约”，不能称为功能缺失。

## 已有事实

| 面 | 已实现 | 证据 |
| --- | --- | --- |
| 基础 | 明/暗、中性表面、品牌操作、字体角色、间距/圆角、两种明确密度、普通 Material 回退 | `lib/theme/app_theme.dart:9-123`；`koi_theme_tokens.dart:53-102` |
| 标准主题 | AppBar、Card、InputDecoration、Filled/Elevated/Outlined/Text/IconButton、ListTile、Chip、Menu/MenuButton、Dialog、NavigationBar/Rail、Divider | `app_theme.dart:124-243` |
| 确有价值的配方 | 选中列表标记/独立焦点、搜索装饰、可换行工具栏、限宽阅读区、属性行 | `lib/widgets/koi_selectable_list_tile.dart` 等 |
| 标准能力组合 | `KoiMenu` 基于 MenuAnchor/MenuItemButton；Popover 处理焦点/语义/关闭；工作区壳组合 Material 导航与自适应面板 | `lib/widgets/koi_menu.dart:44-74`，`koi_popover.dart`，`koi_workbench_frame.dart` |
| 已受测交互 | 中文200%、comfort目标、selected+focus、disabled不可激活、菜单/浮层关闭、焦点恢复、分栏键盘/RTL、状态跨resize | `test/koi_design_behavior_test.dart`、`koi_overlay_accessibility_test.dart`、`koi_platform_layout_test.dart` |

## 明确差距及优先级

### 1. 先修契约偏离

- **设置菜单不能显示当前选择。** `DESIGN.md:163,165` 要求可勾选项和当前值；`KoiMenuItem` (`koi_menu.dart:5-15`) 只有 label、icon、enabled、callback。工作台主题菜单 (`workspace_shell.dart:177-208`) 列出系统/明/暗三个操作，却不能表达正在用哪一个。密度通过“反向操作名称”表达，缺少稳定的已选状态。扩展现有菜单模型的 optional checked/shortcut 表达，或直接使用 Material `CheckboxMenuButton`/`RadioMenuButton`，不创建第二套菜单交互引擎。快捷键标签必须对应宿主真实 Shortcuts/Actions；显示标签本身不注册快捷键。
- **规范说清晰2像素焦点环，实现覆盖不全。** `DESIGN.md:100`；列表 `koi_selectable_list_tile.dart:69-76` 与输入 `app_theme.dart:155-157` 已实现；共用 `ButtonStyle` (`109-123`) 没有 focused side，MenuButton 也没有；它们使用 Material 默认状态层。应明确标准：为支持 side 的主题补独立 focus ring，或把文档约束缩小到指定控件并在 Lab 展示实际反馈；不能把 Material 默认反馈误报为无焦点能力。
- **强弱边界要保持分工。** 输入已使用 `outline`；工作区结构线使用 onSurface 6%；`weakBorder` 是 outlineVariant，不能在新增控件时拿弱结构线替代必要输入/勾选边界。

### 2. 本轮适合补齐的 ThemeData 家族

| 家族 | 当前情况 | 最小稳定契约与实现方式 |
| --- | --- | --- |
| Checkbox / Radio / Switch | 无专属主题；工作台待办正在消费 Checkbox (`tasks_page.dart:143`) | 使用标准组件；checked 使用 primary/onPrimary；unselected 使用明确边界；disabled 优先于 selected/hover；comfort命中区≥48，compact为指针设置但不强行把 Material Switch 压成32高。Radio 示例采用当前 SDK 的 RadioGroup。 |
| SegmentedButton / FilterChip | Segmented 未设置；Chip 只设文字/底色/圆角 (`186-192`) | 统一 selected、unselected、disabled 与控件圆角；单选/多选由控件原生API承担；无新 `KoiSegmentedControl`。 |
| DropdownMenu / PopupMenu | MenuAnchor 已统一，另外两类未统一；Lab 使用 legacy DropdownButton (`main.dart:97`) | 将新表单选择示例统一到 DropdownMenu；输入高度/字体/菜单表面继承同一主题；保留已有消费者兼容性，不进行全仓破坏性替换。PopupMenu 若继续使用则同步表面/圆角/字体。 |
| Tooltip / SnackBar / MaterialBanner | 都未设主题；真实 App 正在消费，风格将落到 Material 默认 | Tooltip 使用可读中性浮层、统一字体/圆角；SnackBar 是短时反馈，操作按钮可见；Banner 是持久错误/需要行动，与内容布局同色系。不要把所有反馈设成红色，也不从 message 文本推断严重性。 |
| TabBar / DataTable | 无主题、Lab无示例 | Tab 指示器/label与中性表面协调；标准横向滚动Tab。DataTable统一标题/正文/selected/hover/分隔线/最小行高；不承诺ThemeData能提供虚拟化、冻结列、大数据表格。 |
| Slider / ProgressIndicator / Scrollbar | 未设主题；工作台已有真实视频/音量 Slider | 保留标准键盘与semantics；统一颜色、轨道、进度与滚动条可见反馈；不改业务进度真实性。Scrollbar 不全局强制 `thumbVisibility: true`，否则无合适 ScrollController 的消费者可能断言。 |
| 输入状态 | 普通/焦点已有；error/disabled 未明确设定 | 使用 `InputDecorationTheme` 补 error/focusedError/disabled 边界和错误字样；保留 Form 验证、选择、IME、光标等标准行为。通过真实 `TextFormField` 状态验证，而非仅检查theme对象。 |
| Buttons | 五类尺寸已有，但状态策略分散于 SDK 默认 | 继续 ButtonStyle；最少可显示 Filled、Filled tonal、Outlined、Text、Icon 的正常/hover/focus/disabled；Text/Outlined作为低强调动作。不要全局手写一个 resolveWith 抹掉每种按钮不同的对比关系。 |

建议按此表一次补齐“共享样式与可运行样例”，而不是增加十几个只转发参数的 KoiXXX 包装。对于平台原生 `.adaptive` 控件，需要标明其可能采用 Cupertino/AppKit 风格，不承诺 Material ThemeData 完整控制它们。

### 3. UI Lab 应变成组件目录

当前 `examples/ui_lab/lib/main.dart:200-307` 只有：FilledButton启用/禁用、Menu/Popover、Search/TextField、字体两行、toolbar。状态页只有空/错/加载，布局页只有说明。`test/ui_lab_test.dart` 仅三条综合测试，不能证明控件全集可用。

建议保留现有真实主题、密度、字号、长中文、RTL、reduce-motion和宽度开关，再按任务分类增加可交互目录：

1. **基础与动作**：表面/字体预览，五类按钮、图标tooltip，disabled与键盘焦点，点击计数一次。
2. **表单与选择**：可输入表单（普通、必填错误、只读、禁用）、Checkbox三态、RadioGroup、Switch、DropdownMenu、SegmentedButton、FilterChip；有真实值与重置。
3. **数据与导航**：TabBar、可选择/可排序的小 DataTable、列表长文本、ScrollBar；窄容器使用局部横向滚动，不压缩触摸目标。
4. **浮层与反馈**：Menu（选中、禁用、快捷键标签）、标准 AlertDialog（取消/确认及焦点返回）、Popover、SnackBar（可撤销示例）、可关闭 Banner、确定/不确定进度。
5. **工作区配方**：现有 workbench resize、侧栏、详情、history、文字状态保留。

不把全部示例硬塞进一个无穷长页面。Lab页面状态由自身State持有，切分类/主题/密度不能清空输入与选中值。示例必须实际调用 Material 控件，展示的是主题产品，不是绘制静态“像组件的卡片”。

## 最小可测契约

- 两种主题/密度里，标准选择控件 disabled 不改变值，菜单 checked 反映宿主值，已禁用项无回调。
- 标准输入错误能够显示/修正，提交不会绕过 Form validator；中文输入、长错误文字、200%字号无溢出。
- 菜单、dropdown与dialog通过键盘操作一次完成；Escape关闭并返回触发器，Tab顺序遵从视觉组织。
- comfortable的真实可交互目标≥48；compact允许缩小但文字放大后自动增高，不能fixedSize锁死。
- 320宽＋200%字下表单动作换行，Tab/DataTable局部滚动，消息/对话框可到达。
- 浮层背景与正文有层次；必要文字/焦点保持现有对比测试。新增“实际颜色配对”而非只镜像theme字段常量。
- 现有 resize/router/编辑器生命周期测试继续保持；新主题不能用更换组件树/Key强制刷新。

本审计没有确认 macOS/iOS/Windows/Linux/Android/Web 的真实逐端表现，没有确认 VoiceOver/TalkBack/Narrator。跨端运行另记，不从 Material 基类或 Widget 测试推导完成。
