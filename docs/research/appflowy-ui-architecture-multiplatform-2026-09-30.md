# AppFlowy 对 Koi Flutter 蓝图的 UI 架构和多平台借鉴研究

AppFlowy 对我们的价值很高，尤其适合学习复杂桌面 UI、可扩展编辑器和原生数据核心的组织方式。建议保留 Koi 当前的 Feature 分层、Riverpod、类型化 go_router 和 Dart Workspace，优先增强设计系统、工作区组件、多端展示与平台能力装配。引入成本最大的 Rust 核心和协作系统，应由具体产品需求触发。

研究日期为 2026 年 9 月 30 日。比较对象是 Koi 当前本地工作树，包括已有未提交改动；本文是研究建议，尚未改变蓝图的架构契约、脚手架或业务实现。

本次固定了三个源码版本：

| 对象 | 阅读版本 | 能证明的范围 |
| --- | --- | --- |
| AppFlowy 主仓库 | `5cf3a365dec0d59f64bad1ee4bb1050471a39b93`，当前查询到的 main | Flutter 客户端、Dart 桥接、Rust 本地核心、组件与 CI 的公开实现 |
| appflowy-editor | `470c4e77c71b63f693ce0923a927afcd667d6f3b`，主应用实际固定的依赖 | 该依赖版本的编辑器扩展接口、transaction 和状态拥有者 |
| AppFlowy-Web | `31233fcc928b34de7bb12f8ca6fa0e24e9e0063f`，当前查询到的 main | Web 项目的 README 和依赖、构建与测试脚本 |

GitHub 当前最新公开发布为 **0.14.5，发布于 2026 年 9 月 22 日**，发布页指向主仓库上述提交；该源码的 Flutter pubspec 仍写 `0.11.4`。因此，本文按读取的代码说明结构，发布说明只用作版本背景与回归场景线索，不能据此认定已验证发布二进制的所有行为。[发布记录](https://github.com/AppFlowy-IO/AppFlowy/releases/tag/0.14.5)、[主应用依赖](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml)

**先确定我们要借什么。**

| 方向 | AppFlowy 的实际做法 | Koi 当前代码 | 建议 |
| --- | --- | --- | --- |
| UI 设计系统 | primitive 与 semantic 颜色 token、独立主题数据、基础交互组件、展示 App | `koi_ui` 有 Material 主题及 loading、empty、error 组件 | 优先补语义 token、常用交互组件和 UI Lab |
| 桌面工作区 | 侧栏、可拖动分隔线、多标签页、详情面板、焦点分组、快捷键 | Admin 示例主要按 960 宽度切换 rail 与 bottom bar | 做一个可复用工作区样例，按产品需要抽取组件 |
| 多端交互 | 桌面与移动有不同页面，共用数据库控制器和部分状态逻辑 | 已有宽窄布局；尚未看到成体系的输入与平台能力样例 | 同业务用例下提供不同展示入口，布局与输入分别判断 |
| 业务架构 | Flutter 页面与状态、Dart 服务适配、FFI、Rust 数据模块 | 已有 domain/data/application/presentation 与注入契约 | 借鉴边界及数据流，继续使用 Riverpod |
| 扩展机制 | 页面插件、编辑器 block builder、Rust 事件模块分别扩展 | `koi_modules` 已有路由贡献及模块会话拥有者 | 复杂产品按需增加类型化 UI 贡献，复用现有生命周期 |
| 原生与 Web | Flutter 客户端使用 native FFI；完整 Web 是独立 React 项目 | 最小项目可生成六端；已有平台矩阵定义 | 为真实能力记录各平台实现与验收证据，不能只看平台目录 |

AppFlowy 的大型代码库同时有新旧 UI 包、BLoC、Provider、GetIt，以及 `workspace/user/plugins/features` 等组织方式。它能展示复杂产品的实际工程处理，也有演进留下的边界差异；我们应逐条吸收经源码支持的做法。

**1. UI 构建值得学习到组件行为这一层。**

AppFlowy 把基础颜色和用途分开维护：primitive 表示基础色值；semantic 表示正文、边框、背景、填充、选中、错误等用途，并分别提供 light/dark 映射。生成器读取三个 JSON 文件，输出 Dart 颜色和主题实现。间距、圆角和阴影另在 `shared.dart` 维护，不能把整个设计系统描述为全自动生成。[颜色生成器](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/script/generate_theme.dart#L13)、[共享尺寸与阴影](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/theme/data/shared.dart)

独立的 `AppFlowyThemeData` 聚合文字、图标、边框、背景、surface、spacing、radius、shadow 等数据。组件读取用途对应的 token，主题变化由 `InheritedTheme` 和插值处理。它为复杂应用提供了 Material 之外的产品视觉语义。[主题数据](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/theme/definition/theme_data.dart#L9)、[主题传播](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/theme/appflowy_theme.dart)

我们的 [AppColors](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/packages/koi_ui/lib/theme/app_colors.dart) 目前主要按品牌色命名，[AppTheme](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/packages/koi_ui/lib/theme/app_theme.dart) 已有 Material 3 的 ColorScheme 和组件样式。下一步可在此基础上用 `ThemeExtension` 增加少量产品语义，例如面板背景、弱边框、辅助文字、选中背景和拖放指示色，同时整理 spacing、radius、density。通用语义继续交给 ColorScheme/TextTheme，避免并行维护两套相同定义。

`AFBaseButton` 集中处理 hover、disabled、鼠标指针、Focus、ActivateIntent 和焦点环；filled、outlined、ghost 等变体复用该基础行为。菜单和 modal 进一步把容器、条目及 header/body/footer 拆开组合。这比在业务页面重复组合 GestureDetector、Container 和颜色判断更容易保持一致。[基础按钮](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/component/button/base_button/base_button.dart#L17)、[菜单](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/component/menu/menu.dart)、[Modal](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/component/modal/modal.dart)

建议先整理高频组件的行为契约：按钮、可选列表项、菜单、popover、带操作的 section、可调整面板。能够通过 Material 现有组件和样式完成的行为，优先保留其键盘与焦点基础；定制组件可用 FocusableActionDetector。展示组件接收不可变数据和语义回调，业务容器通过 Riverpod 连接用例。[Flutter 输入指南](https://docs.flutter.dev/ui/adaptive-responsive/input)

Popover 尤其值得看。旧 `appflowy_popover` 提供锚点/鼠标位置展示、FocusScope、Escape 关闭和互斥；新 `appflowy_ui` 中的 AFPopover 又有 controller、外部点击分组和栈顶弹层管理。这说明复杂 UI 的成本包括焦点、嵌套弹层和关闭顺序。两套实现并存也是迁移成本，建议我们为一套公开 API 收敛行为，并测试 Escape 后焦点恢复、滚动时定位和页面销毁清理。[旧弹层](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_popover/lib/src/popover.dart#L352)、[互斥管理](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_popover/lib/src/mutex.dart)、[新弹层](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/lib/src/component/popover/popover.dart)

AppFlowy 的组件展示 App 可以切换明暗主题，分别查看 Button、TextField、Modal、Avatar、Menu、Dropdown Menu。建议给 Koi 增加 `examples/ui_lab`，展示主题、密度、长中文、loading/disabled/hover/focus 和窄容器情况，作为开发与视觉检查入口，再用有行为意义的测试补充验证。[组件展示 App](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_ui/example/lib/main.dart)

两个工程细节需要保留：本次源码中 `appflowy_ui` README 的清单落后于已有 menu/popover 源码；该包树下未见独立 test 目录，展示 App 不能当成测试通过证明。另外颜色生成器写入当前时间，直接复制会产生重复生成差异。我们的 token 生成流程应有确定输入、稳定输出与明暗语义完整性检查。

**2. 多平台要共享业务意图，并给交互留出差异。**

桌面主界面有 HomeLayout、侧栏、SidebarResizer、标签页、编辑面板、通知面板和快捷键。侧栏缩窄时可以作为 drawer 展示，部分区域用 FocusTraversalGroup 与 RepaintBoundary 隔离。移动端另有 MobileHomeScreen、SafeArea 和底部导航分支；移动路由使用 StatefulShellRoute.indexedStack 保留各分支状态。[桌面入口](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/workspace/presentation/home/desktop_home_screen.dart)、[桌面布局](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/workspace/presentation/home/home_layout.dart)、[移动入口](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/mobile/presentation/home/mobile_home_page.dart)、[路由装配](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/generate_router.dart#L46)

看板提供了更直接的例子：`BoardPageTabBarBuilderImpl` 将同一个 DatabaseController 传给 DesktopBoardPage 或 MobileBoardPage。桌面拖动卡片最终调用 controller 的 moveGroupRow 等操作。展示差异由页面承担，数据库读取、移动行和字段状态在共享控制器中处理。[看板分支与控制器传递](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/database/board/presentation/board_page.dart#L41)、[共享数据库控制器](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/database/application/database_controller.dart#L85)

映射到 Koi，可让一个 Feature 共用 application、repository 和 provider，在 presentation 中组织 desktop/mobile/adaptive 页面。基础内容较简单时仍共用一个页面；当导航、详情编辑、拖放、工具栏和键盘行为有明显差异时，再拆展示入口。无需为了两种 UI 复制整套 Feature。

同时要改进它较多基于操作系统分支的方式。**操作系统、可用空间、当前输入方式和平台能力是不同判断。** 桌面窗口也可能很窄，平板也可能接鼠标。全窗口布局可用 MediaQuery.sizeOf，局部面板用 LayoutBuilder；输入密度、hover 和快捷键按输入条件处理；原生窗口与文件能力在平台适配层判断。Flutter 官方建议也把公共数据抽象、测量空间和布局分支分开处理。[Flutter 自适应布局](https://docs.flutter.dev/ui/adaptive-responsive/general)

我们现有 [HomeShellScaffold](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/apps/koi_admin_app/lib/features/home/presentation/widgets/home_shell_scaffold.dart) 已按窗口宽度切换导航，这是可用的起点。需要增加的是复杂工作区样例，以及窗口 resize 之后选中项、草稿、滚动位置和编辑会话的持续性。业务状态应由页面外稳定的会话或 provider 拥有，短暂的 hover、焦点、动画仍由 Widget 管理。

**3. 架构重点是状态与原生数据的清晰连接。**

本次追踪的客户端链路可以概括为：

```text
Flutter 页面 / 编辑器
        ↓ 用户意图或 transaction
Dart 状态、用例与服务适配
        ↓ 生成的事件请求与 Protobuf 数据
appflowy_backend / 原生 FFI
        ↓ 事件分发
Rust document / database / folder 等模块
        ↓
本地存储与协作接口

响应经 Dart port 返回；通知经独立 stream 回到 Dart 状态和页面。
```

Dart Dispatch 序列化请求并调用 `async_event`；Rust 将请求提交给独立线程中的 Tokio 运行环境，再通过事件分发器执行对应处理，结果回到 Dart port。Rust 的 `flowy-core` 组合 document、database、folder、user、search、AI、storage 等模块。这里说的 Rust “backend” 包含客户端进程内的本地核心，并非所有请求都发往远端服务。[Dart 请求桥接](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_backend/lib/dispatch/dispatch.dart#L50)、[Rust 调度与回传](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/rust-lib/dart-ffi/src/lib.rs#L175)、[核心模块组合](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/rust-lib/flowy-core/src/module.rs)、[通知 stream](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_backend/lib/rust_stream.dart)

这对本地媒体、模型、索引或文件工具有借鉴价值：Flutter 构建交互；application 负责用例、任务和会话；data 中的 adapter 调用已有引擎，再把结果映射为业务模型与可观察事件。引擎实现可依据现有能力选择 Dart、Swift/原生插件、FFI 或外部进程。长任务需要取消、进度、错误和迟到结果语义，不能靠页面监听生命周期代替实际任务管理。

Rust 和 Protobuf 应按跨语言边界、计算及协作需求引入。纯 Dart 的简单查询可以继续直接调用 repository。高频 FFI 请求、数据复制与序列化都有成本；本次未测量吞吐、内存或帧率，不能因为用了 Rust 就推导性能优势。

AppFlowy 使用 BLoC、Cubit、GetIt、Provider 和 ValueNotifier。其核心可迁移做法是单向意图、可观察状态、细粒度订阅、资源拥有者和清理时机。我们已有 [状态管理规范](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/docs/architecture/state-management.md) 和 [本地桌面契约](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/docs/architecture/local-first-desktop.md)，可以通过 Riverpod 实现这些行为，没有迁移状态管理框架的证据。

一个值得吸收的粒度例子是数据库 cell：CellContext 由 fieldId 与 rowId 标识，CellController 监听对应字段/单元格，CellMemCache 按字段和行缓存数据。对于大型素材列表或任务列表，我们也应让单项进度按稳定 ID 订阅，再测量重建范围；family 本身不保证局部重建。[单元格控制器](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/database/application/cell/cell_controller.dart)、[缓存](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/database/application/cell/cell_cache.dart)

目录命名不能直接迁移。AppFlowy 的 `plugins/database/domain/database_view_service.dart` 实际发起 Rust 事件请求；一个 RustWorkspaceRepositoryImpl 还导入 presentation 下的 billing 辅助函数。它的 domain/data 边界与我们纯 Dart domain、IO 放 data 的规则不同。建议保留 Koi 的规则，借用具体行为与适配方式。[数据库服务](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/database/domain/database_view_service.dart#L10)、[工作区 repository](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/features/workspace/data/repositories/rust_workspace_repository_impl.dart#L1)

**4. 编辑器最值得借鉴的是可扩展协议与变更模型。**

AppFlowyEditor 的构造参数公开 blockComponentBuilders、字符快捷键、命令快捷键、context menu、样式、header/footer 和 blockWrapper。新 block 类型可以通过注册 builder 加入，既有类型也能替换。EditorState 拥有文档、selection、undo manager 及输入/滚动/渲染服务；内容变更通过 transaction 表达。[编辑器扩展接口](https://github.com/AppFlowy-IO/appflowy-editor/blob/470c4e77c71b63f693ce0923a927afcd667d6f3b/lib/src/editor/editor_component/service/editor.dart#L22)、[EditorState](https://github.com/AppFlowy-IO/appflowy-editor/blob/470c4e77c71b63f693ce0923a927afcd667d6f3b/lib/src/editor_state.dart#L83)、[Transaction](https://github.com/AppFlowy-IO/appflowy-editor/blob/470c4e77c71b63f693ce0923a927afcd667d6f3b/lib/src/core/transform/transaction.dart)

主应用将这些能力装配到 editor 页面。DocumentBloc 订阅 transactionStream，TransactionAdapter 将编辑器的树结构操作转换为 Rust 所需的 block/text 动作，再调用 DocumentService；关闭时取消订阅并清理 editor 资源。[编辑器页面装配](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/document/presentation/editor_page.dart#L357)、[文档状态与清理](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/document/application/document_bloc.dart#L109)、[变更适配器](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/plugins/document/application/editor_transaction_adapter.dart#L13)

适用于我们的两类产品建议：

- 如果需要富文本、知识页或块式内容，优先单独验证 appflowy-editor，包括中文 IME、粘贴、序列化、自定义 block、undo/redo 和目标平台。读取的依赖版本没有 AppFlowy Rust backend 依赖，并在 pubspec 声明六端；这些声明仍需具体环境验证。[编辑器依赖与平台声明](https://github.com/AppFlowy-IO/appflowy-editor/blob/470c4e77c71b63f693ce0923a927afcd667d6f3b/pubspec.yaml)
- 如果构建素材、画布或时间线编辑器，可借鉴“内容模型 + renderer 注册 + 语义命令 + 可逆变更 + session”的方式。一次拖动结束、裁剪或参数变更形成业务操作，便于撤销、持久化与测试。不要默认给所有简单页面引入 transaction 系统。

EditorState 这类高频、可变的专用 UI 控制器可以由编辑会话拥有。Riverpod 观察当前文档、dirty、保存进度、错误和选中摘要，不必复制每次光标或输入变化为一份大型业务状态。退出会话时同时处理保存、订阅与控制器清理。

**5. 三种扩展机制要分别理解。**

| AppFlowy 中的机制 | 实际作用 | 对 Koi 的对应建议 |
| --- | --- | --- |
| UI 页面 Plugin/PluginBuilder | 把 view 类型映射为页面、导航信息和插件实例 | 宿主按需装配类型化页面或工具贡献 |
| Editor block builder 与快捷键 | 把内容节点映射为渲染组件与编辑行为 | 在复杂编辑器内部提供稳定扩展接口 |
| Rust AFPlugin 事件模块 | 注册业务事件与对应 manager | 引擎确有模块化需求时才设计事件协议 |

主应用的 PluginLoadTask 在编译好的代码里注册内建插件；PluginSandbox 保存 builder/config 并创建实例。读取版本的 PluginRunner 为空类。因而这里不能用来证明任意第三方插件的动态安装、热加载或隔离运行能力。[插件接口](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/plugin/plugin.dart)、[注册容器](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/plugin/src/sandbox.dart)、[加载任务](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/load_plugin.dart)、[Runner](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/plugin/src/runner.dart)

Koi 当前的 [KoiModuleCatalog](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/packages/koi_modules/lib/src/module_catalog.dart) 已提供不可变的路由/导航贡献并检查重复项，[模块 runtime](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/packages/koi_modules/lib/src/module_runtime.dart) 管理创建、切换、清理和过期会话。复杂产品可在这个基础上增加 toolbar、command、panel 等有限贡献；为其定义输入、输出、状态拥有者与释放范围。没有必要为了普通两页应用建设一个通用插件平台。

**6. 原生平台和 Web 要按真实能力分别验收。**

AppFlowy 的 `ffi.dart` 导入 dart:ffi/dart:io，为 Linux、Android、macOS、iOS 和 Windows 打开动态库或进程符号，其余平台抛 UnsupportedError。该桥接没有浏览器实现。完整 Web 产品在独立的 AppFlowy-Web 仓库，其 README 和 package.json 明确使用 React、TypeScript、Vite，以及 Web 侧编辑和数据依赖。[原生桥接](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/packages/appflowy_backend/lib/ffi.dart#L15)、[Web 项目说明](https://github.com/AppFlowy-IO/AppFlowy-Web/blob/31233fcc928b34de7bb12f8ca6fa0e24e9e0063f/README.md)、[Web 构建与依赖](https://github.com/AppFlowy-IO/AppFlowy-Web/blob/31233fcc928b34de7bb12f8ca6fa0e24e9e0063f/package.json)

应分别陈述：原生 Flutter 客户端覆盖多个原生平台；独立 editor 包声明支持 Web；完整 AppFlowy Web 使用另一套前端。仓库里的 `web/` 目录及零散 isWeb 判断，不能证明整个原生客户端在浏览器可用。这也不意味着我们的项目应该改用 React；是否拆 Web 前端，要看目标产品是否需要浏览器原生编辑、内容发布或无法在浏览器实现的原生引擎。

建议在宿主 bootstrap 注入明确的平台能力与实现，例如窗口管理、文件导入、rich clipboard、媒体引擎、系统分享。Feature 依赖对应端口；缺失能力返回明确的 unsupported/unavailable 结果，并使 UI 给出可操作状态。简单产品先在 App core 中实现，出现跨 App 稳定复用后再抽 package。

AppFlowy 启动流程把初始化分为 LaunchTask，依次处理本地 SDK、窗口、插件、文件、国际化和平台监听，也给任务提供 dispose。窗口配置进一步区分 Windows 与 macOS/Linux，保存大小、位置与最大化状态。这是“宿主装配并拥有资源”的可用样例；若我们增加任务式 bootstrap，需要定义失败回滚、清理顺序与可注入测试依赖。[启动流程](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/startup.dart#L234)、[窗口适配](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/windows.dart)、[窗口状态](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/app_window_size_manager.dart)

AppFlowy 的 Flutter CI 定义了三种桌面 OS 的构建准备，Flutter unit/cloud/integration 测试主要在 Linux 跑，integration 分九组；移动构建另通过 Codemagic 工作流触发。它值得借鉴的是实际交互与原生核心一起验证，以及将较大测试拆分运行。本次未查询这些工作流当前执行结果。[Flutter CI](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/flutter_ci.yaml)、[移动 CI](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/mobile_ci.yml)

Koi 当前 [.github/workflows/quality.yml](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/.github/workflows/quality.yml) 已定义生成新项目后的 Web/Android/Linux、iOS/macOS、Windows 构建矩阵；不能再按旧状态说只有 Web 构建。需要补充的是目标平台上真实新增能力的运行检查，而不是重复增加已有矩阵。本次只阅读定义，未执行或证明该矩阵通过。

AppFlowy 的桌面快捷键测试验证剪切、复制和剪贴板结果；移动工具栏测试验证选择、插入链接和实际文档内容。Koi 的对应验收可以围绕用户动作，而不仅是 widget 能否渲染。[桌面交互测试](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/integration_test/desktop/document/document_shortcuts_test.dart)、[移动交互测试](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/integration_test/mobile/document/toolbar_test.dart)

**建议分三步落地，每步都有独立产物。**

| 顺序 | 小范围产物 | 推荐位置 | 验收重点 |
| --- | --- | --- | --- |
| 第一阶段 | 语义主题、少量高频组件、UI Lab | 现有 `packages/koi_ui` 与新增可选 `examples/ui_lab` | 明暗、长中文、焦点/hover/disabled、token 生成稳定性 |
| 第二阶段 | 可缩放工作区、共享导航/动作、桌面与紧凑交互样例 | 先在受测样例和 App shared 实现，稳定后抽取 | resize 保留草稿与选择；Tab/Enter/Escape；弹层关闭后恢复焦点 |
| 第三阶段 | 一种真实平台端口及能力差异样例；必要时接 editor | App core、Feature data/application；复用模块会话契约 | 目标端实际可用；unsupported 状态；取消与迟到结果；保存恢复 |

当前 [blueprint.py](/Users/max/Workspace/SourceCode/mrkoi/koi_blueprint_flutter/blueprint.py:343) 从 starter_app 创建最小项目，活动 workspace 默认只含 App 和 koi_core；完整样例/包是惰性的参照快照。增强 koi_ui 后，必须提供实际消费它的受测样例或可选接入流程，不能把研究文档或参照源码当成新项目已经具备的运行能力。

优先把前两阶段放进蓝图研究与样例建设。Rust/CRDT、全局事件协议、动态插件、多进程或独立 Web 前端，只有出现实际产品需求再评估。这样可以在保留最小项目简洁性的同时，增加复杂桌面和多端产品所需的可复用能力。

本次完成了公开源码快照、关键依赖、release 信息与 Koi 当前实现的静态对照，抽样追踪主题/组件、看板多端展示、编辑器变更、原生桥接、启动和 CI。未编译或运行 AppFlowy，未执行 Koi 全门禁、设备测试或性能测量；所有落地阶段均为建议，尚未实施。
