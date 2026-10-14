# ChatGPT-Contents → Flutter UI Kit：只读提取结果

读取日期：2026-10-01。来源是用户指定的 `/Users/max/Downloads/ChatGPT-Contents`，版本 **26.928.20755 / build 12246**。包内包含 Codex、ChatGPT、浏览器等不同表面的共享资源；不能将任意规则等同于所有产品页面的统一规范。

这份安装包可以提供足够多的 token、组件变体和交互实现证据，支持一次系统化的 Flutter 主题完善。它不是原始设计仓库，也没有在已检查的资源命名中发现可直接当作权威的 `DESIGN.md`、Figma 文件或完整交互规范。`webview` 没有 `.map` 文件。不应把“读到打包 CSS/JS”写成“已恢复官方全部设计系统”。

机器记录：[bundle-tokens.json](bundle-tokens.json)，包含 176 条选定 CSS 声明、11 条 JS 行为证据、资源 SHA256、完整选择器和字符偏移。复现：[extract_bundle_evidence.py](extract_bundle_evidence.py)。脚本按 ASAR 索引定位、读取选定文件，不解包应用，不读取用户数据；只输出必要声明和短检索片段，不保存完整厂商源码。之前对照：[2026-09-30 报告](../../desktop-ui-design-comparison-2026-09-30.md)。

## 1. 已确认的静态事实

| 范畴 | 包内实现事实 | Flutter 映射建议（是 Koi 的选择） |
| --- | --- | --- |
| 字体 | 系统 UI 栈；内容字体可独立配置；等宽字体独立。通用 `text-base=14px`，Electron 覆盖 `text-sm=13px`、`text-xs=12px` | `TextTheme` 统一角色；UI 14、辅助 12、按钮/菜单 13，文档正文独立 16；系统字体由平台提供 |
| 排版 | `font-text-sm` 为 `.875rem/1.25rem`，`md` 为 `1rem/1.5rem`，`xs` 为 `.75rem/1.125rem` | 在 Koi 设计规范中用明确逻辑像素/行高表达，不把 rem 当作永远等于 16px |
| 间距 | 基础 spacing `.25rem`，控件 gutter 单独分档 | 保留 4 像素网格，允许 6/10 等光学间距；不能一个 padding 套所有控件 |
| 控件大小 | control size 从 `1.25rem` 至 `3rem`：若根字号 16px，即 20/22/24/26/28/32/36/40/44/48 | 无需复制十档。Koi compact 32、comfortable 48，必要小型图标视觉尺寸与触摸命中分别定义 |
| 圆角 | base radius 为 `.125/.25/.375/.5/.625/.75/1/1.25/1.5rem` | Koi 选取角色：列表 6、控件 8、浮层 12/16、工作区按既有外壳规格；避免全部胶囊化 |
| 动效 | 基本 150ms，舒缓 300ms；可读到 reduced-motion 分支将某些导航动画降为 0 | 保留标准 Flutter 动画，扩展组件通过 `MediaQuery.disableAnimationsOf` 尊重减少动态效果；不必强行复刻弹簧 |
| 焦点 | 按钮 `:focus-visible:after` 为 2px ring，默认 offset 2px；focus 与 selected 是不同状态 | 标准控件用 `WidgetStateProperty` 分别表达 focused/hovered/pressed/selected/disabled；焦点不可仅靠低对比填色 |
| Hover | 按钮 hover 样式限定 `@media (hover:hover)`，排除 disabled | 使用 Material 控件自己的 MouseRegion/Focus/Actions 行为，避免另写点击模拟器 |
| 禁用 | 语义 disabled，与 dimmed/ghost 的 `.4` opacity 或独立禁用颜色组合 | 禁用需阻止回调并保留可读语义；不能只有颜色变浅 |
| 边界 | hairline `.5px`；默认 border 支持按前景色 8% 混合；控件边界与结构边界有不同 token | 弱结构线独立于可识别的输入框、焦点边框；禁止把 outlineVariant 用作所有工作区分割线 |
| 菜单 | 通用与 Electron 有不同配方；Electron 外 gutter 4px、字号 `text-sm`、条目纵 padding 5px（根字号16时）、背景为独立 elevated surface | `MenuThemeData` + `MenuButtonThemeData` + `MenuAnchor/MenuItemButton`；compact 与触摸密度分开 |
| 浮层 | Popover 的 radius 和 elevated surface 独立；side offset 默认8、碰撞 padding20、锚点脱离时隐藏 | 标准菜单/对话框优先；自定义 Popover 只承担任意内容锚定、碰撞/焦点/销毁等标准组件未覆盖的场景 |
| Tooltip | 独立的背景/文字/圆角/字号/padding，普通与 compact 变体不同 | `TooltipThemeData`，保留默认键盘/长按能力；不要用普通 Text 的悬浮副本代替 |

这些是有作用域的声明；不同窗口类型、主题、组件变体、透明度和级联会覆盖默认值。资源文件名也不可靠：例如 `navigation-toolbar-presentation-*.css` 本次读到的主要是 RadioGroup 样式，不能凭文件名宣称它给出了标题栏完整尺寸。

## 2. 侧栏、标题栏、内容绝不能只按一个背景名套色

可追溯链路主要在 `app-shared-b42a855b3317.css` 与 `app-initial-a3898107ddbb.css`：

| 静态角色/上下文 | 源码关系 |
| --- | --- |
| `color-token-side-bar-background` | 指向 `app-color-background-surface-under` |
| `color-token-main-surface-primary` | 指向 `app-color-background-surface` |
| `app-color-background-surface` 默认 | 明色 `gray-fixed-0 (#fff)`，暗色 `gray-fixed-900 (#181818)` |
| `app-color-background-surface-under` 默认 | 明色 `gray-fixed-50 (#f9f9f9)`，暗色 black |
| `app-color-background-shell` | 指向 `color-surface-tertiary`，后者又指向 editor-opaque |
| editor-opaque 默认 | 明色 gray100（支持色混合时40%），暗色 gray800 (#212121) |
| elevated-primary / opaque | 暗色 gray800 / gray750 (#282828)，透明模式另有覆盖 |
| 页面壳左面板中的 `.sidebar-navigation` | 特定 PageSurface 布局将其设置为 `color-surface`，支持混合时为65% + transparent |
| FloatingHeader（非 content-surface） | 使用 `header-tint`，不能从这条规则确定最终背景值 |
| PageSurface 的主内容 | 使用 `color-surface`，有圆角角色；统一 tab-strip 模式又存在额外背景覆盖 |

因此：**包里确实有“外壳 / 支持面板 / 正文 / 浮层”的分层机制，但恢复任意用户截图的精确 RGB 仍需该窗口的运行时主题、背景材质和布局状态。** 不能把上面的默认 black sidebar token 当成截图的实际侧栏颜色，也不能据此把资料列表与正文涂成同一色。

Koi 应建立独立、确定性的三种角色：`chromeBackground`（系统标题栏和图标栏）、`panelBackground`（资料侧栏/详情）、`contentBackground`（编辑/正文）。资料列表仍属于工作区内容容器，颜色可以不同。当前修正采用的 `#222222 / #1C1C1C / #101010` 是依据用户截图和 Koi 层级目标制定的配方，不是从静态 token 唯一推导出的 Codex 官方配色。轻微色差负责分区，常态结构线低强调，hover/focus 时才加强 resize 把手。

## 3. 可以复用的交互契约

以下是包内共享 JS 原语的实现事实；没有进行这份 App 的实际点击/键盘/读屏验收，业务调用还可能覆盖它们。

- **菜单触发**：enabled 时 Enter/Space 切换打开，ArrowDown 打开；禁用项不执行这些分支。
- **菜单导航**：菜单原语定义方向、Home/End/PageUp/PageDown 边界键；左右子菜单方向适配 RTL。typeahead 过滤 disabled，搜索 buffer 一秒清空。
- **菜单选择**：选择启用项只触发一次 cancelable select；未被阻止时关闭。关闭通常把焦点还给触发者，外部交互有例外。
- **弹层关闭**：共享 dismissable layer 只在自己是最顶层时处理 Escape，并允许调用方取消默认行为；不能让底层页面快捷键抢走弹层 Escape。
- **模态对话框**：共享 `DialogContentModal` 在打开时限制焦点和外部指针，关闭默认还原触发焦点。
- **Popover**：默认非模态、可配置自动聚焦；锚定带碰撞避免及脱离隐藏；可选 hover 的默认延迟150ms且排除触摸 hover；定时器在卸载时清理。
- **Popover 的缺口**：本地 wrapper 明确传入了自定义 `onEscapeKeyDown`。单看这段不能断言最终 Escape 一定关闭，也不能据其他原语推断其全部行为。

Koi 的优先策略是保留 Material 的 `MenuAnchor`、`MenuItemButton`、`showDialog`、`AlertDialog`、`Shortcuts/Actions`、Focus 遍历机制。静态 UI 看起来相同但 Tab、Enter/Space、关闭焦点或 disable 行为丢失，不算可用复刻。

## 4. 建议交付到 Koi 的范围

| 层 | 直接完善标准能力 | 何时需要 Koi 自定义 |
| --- | --- | --- |
| Foundation | ColorScheme、TextTheme、ThemeExtension、VisualDensity、MaterialTapTargetSize | 外壳/资料面板/正文/浮层等产品语义 token |
| Action | Filled/Outlined/Text/IconButton、MenuAnchor/MenuItemButton 的主题与状态 | 确有重复页面配方才做轻量组合；不创建平行 Button 引擎 |
| Input | InputDecorationTheme、Checkbox/Radio/Switch/Slider、DropdownMenu/SearchBar、Chip/SegmentedButton | 搜索框清除按钮等轻量语义组合，仍委托 TextField |
| Navigation | NavigationRail/NavigationBar/Drawer/TabBar 的主题和标准焦点 | 自适应工作区、可调面板、原生标题栏桥接 |
| Feedback | Dialog、BottomSheet、SnackBar、Tooltip、ProgressIndicator | 通用空/错误/重试内容配方，异步业务仍由宿主注入 |
| Data | ListTile、DataTable、Divider、Scrollbar | 选择行和属性行的统一配方；排序/筛选业务留在 App |
| 验证 | UI Lab 同时真实消费上述标准控件，提供明暗/密度/200%/长中文/disabled/focus/error | screenshot 与行为证据分别记录，不能用组件展示页宣称全部目标平台可用 |

本报告给出的是可复现的本地研究与 Flutter 映射依据。企业级可用性最终需要组件状态矩阵、键盘/触摸/读屏、长文本/缩放、错误/恢复和平台真实运行证据。读取安装包本身不会自动补齐这些验收。
