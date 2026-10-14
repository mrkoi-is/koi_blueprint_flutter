# Koi Workbench 增强实施与验收记录

日期：2026-09-30。代码实现和本机验证已完成；未提交、推送、发布或部署。缺少目标环境和工具权限的项目保留 NOT_RUN。

## 工作树与交付范围

实施前保存原有工作树状态和 235 个源码文件的哈希/副本：

`/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi-blueprint-baseline-20260930-9wo37h5j`

原有未提交工作保留。新增统一 `koi_ui` 主题/token/密度、六个公共组件、UI Lab、Workbench 三视图、真实导入与缩略图任务、Native/Web 内容存储、两种生成模板、平台配置、AI/架构门禁、浏览器门禁与 CI。活动模板成员均为 App、`koi_core`、`koi_ui`；媒体/文件依赖只进入 workbench。

文本资料、媒体素材和待办/后台任务共用一个工作区会话，导航使用类型化 `StatefulShellRoute.indexedStack`。Native 保存管理目录内的副本与版本化快照，Web 保存实际 IndexedDB Blob；临时预览 URL 按展示会话释放。

## 最终本地门禁

| 项目 | 实际结果 |
| --- | --- |
| `python3 blueprint.py validate` | PASS：生成、格式、架构、AI 资产、分析、测试、浏览器及覆盖率门禁 |
| 全仓手写覆盖率 | **86.32%，3143/3641 行** |
| 生成 workbench 独立完整门禁 | PASS，**82.86%，1944/2346 行**；仅 App + koi_core + koi_ui |
| Workbench VM 行为 | 58/58；包含核心 36 项及展示/播放器/装配测试 |
| Workbench Chrome 浏览器行为 | 8/8：实际 IndexedDB/Blob、损坏数据、清理与图像 |
| UI 与 UI Lab | 23/23；320、600、1024、1440 宽度及 200% 字号、长中文、焦点/浮层/调整面板 |
| Python 脚手架 / AI 与平台配置 | 28/28、22/22 |
| 架构正反回归 | 74/74；16 个活动成员通过架构检查 |
| 生成与递归 smoke | PASS：两种模板、四种递归组合、改名/中文路径、三类 Feature、独立业务 module 及其 API Feature |
| 最终源码 minimal→workbench 复验 | PASS；逐字核对最终工作区核心实现后执行生成项目完整 validate |

VM 未采集的 170 行浏览器实现按零命中加入覆盖率分母，没有扩大目录排除。真实浏览器行为单独验收，未伪计 VM 命中。

验证覆盖草稿/选择/滚动、router、工作区及播放器在导航和 resize 后的身份保持；保存期间继续编辑、中文重开、写入/损坏错误保留内容；真实字节进度、Stream 取消、暂存清理、迟到结果拒绝、唯一终态及启动 interrupted。媒体失败重试从实际视图执行，保留旧任务记录。

复核修复了三类保存期间取消窗口和旧缩略图清理期间取消窗口：先持久化回滚再删字节；补偿失败保留仍被引用的内容并显示 failed；取消前已经提交的新缩略图保留，等待旧图清理后才进入 cancelled。新增 6 个真实 Native 存储与受控 IO 回归。

## 平台构建与真实运行

最终工作区核心源码 SHA-256：`16bca3ce3ea7ca26091247b5cdd376bfc1f84e43220e7757dad1ca446e2594a7`。

构建宿主的 48 个 App/UI 源文件仅有记录过的项目身份替换；运行宿主的 60 个 App/UI/集成测试源文件逐一校验一致。构建前后再次核对源码与产物 SHA，未手动修改 SDK runner。

| 平台 | 最终构建 | 真实运行 | 范围与限制 |
| --- | --- | --- | --- |
| Android | debug PASS；另以 split-per-abi 生成并 ZIP 实查仅 arm64-v8a 的 APK | NOT_RUN | 未安装到连接设备；构建不代表设备验收 |
| iOS | release `--no-codesign` PASS | NOT_RUN | 未签名、未安装；缺目标 Simulator runtime |
| macOS | 最终集成 debug 宿主与主 App debug 均 PASS | PASS | 实际 Player、PNG/JPEG、横/竖视频、首帧截图、播放/暂停/seek/音量、存储重开与资源释放 |
| Windows | NOT_RUN | NOT_RUN | 当前无 Windows 主机；CI 已配置 |
| Linux | NOT_RUN | NOT_RUN | 当前无 Linux 主机；CI 配置 mpv/GTK 和 Xvfb |
| Web / Chrome | release PASS | PASS | 实际 IndexedDB Blob、暂停首帧、播放控制、URL 撤销与重开恢复；播放器修复后连续两轮通过，最后取消修复后再次通过 |
| Web / Safari | 同一 Web 构建 PASS | NOT_RUN_BLOCKED | SafariDriver session 返回 HTTP 500，要求启用远程自动化；未修改用户设置 |

最终 Web、Android、iOS 三次构建耗时分别为 88.6、23.4、72.6 秒；另一次 Android split-per-abi 为 12.0 秒。iOS 证据包含实际 Dart AOT `App.framework/App`，不仅记录 Runner 二进制。

播放器集成测试通过 fixture adapter 导入；使用真实插件、存储和截图 API。检查截图实际像素，Native 横/竖视频首帧与持久缩略图分别为 5714/5020 色，Chrome 分别为 7437/6927 色；PNG/JPEG 图像缩略图分别为 15360/12706 色。实际验证预览 lease 释放，Web Blob URL 撤销后无法 fetch。

固定依赖：file_selector 1.1.0、media_kit 1.2.6、media_kit_video 2.0.1、media_kit_libs_video 1.0.7。SDK 3.47.2 默认 Android 24 / iOS 15 / macOS 12。视频 fixture 为 H.264 Constrained Baseline、yuv420p、AAC-LC 48kHz；实际五项导入 fixture 合计 86,249 字节，编码/尺寸/哈希见素材 manifest。小型样本结果不外推到所有编码、大小和硬件。

## 真实文件选择器的额外验收

macOS 主 App 通过系统 Open / Go To 对话框选中 `中文资料.md`，实际插件读取并导入 86 字节；编辑器显示正确中文和“32 字 · 已保存”。关闭窗口后只读核对该验收 App 自己的管理快照：资料内容与原 fixture 完全相同，任务为 succeeded，实际进度 86/86；未修改原文件。

此项证明 Native 文本选择与导入。macOS 图片/视频对话框与原生键盘激活本轮未完成额外 UI 验收，键盘与视图行为已有 Widget 测试。

Chrome 真实文件输入成功触发 chooser，但自动设置文件被浏览器扩展的文件 URL 权限拒绝；原生对话框回退未能打开。记为 NOT_RUN_BLOCKED，未更改扩展权限。Chrome fixture 测试已证明后续真实存储和媒体路径，但不能替代该选择器验收。其他平台系统对话框未执行。

## 可留存证据与复跑

最终摘要、运行像素、源码清单、产物 SHA、真实选择器记录和门禁日志摘录已保存到 [evidence/2026-09-30-workbench](evidence/2026-09-30-workbench/validation-summary.json)。完整临时日志的大小和 SHA 也写入摘要，便于核对。

- 最终完整门禁：`/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi-validation-complete-bsc3qkei/validate.log`。
- 四种递归生成：`/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi-generator-complete-3bxtok6b/generator-smoke.log`。
- 最终源码 minimal→workbench：`/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi-final-recursive-source-auzyd__b/recursive-minimal-workbench.log`。
- 平台构建宿主：`/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi-platform-acceptance-ls6vnuym/`。
- 真实运行宿主：`/private/var/folders/lz/612zcv0d71q1c4v_mbpbcz1c0000gn/T/koi_runtime_acceptance_r440woi4/`。

早期失败日志保留：生成时复制了尚未冻结的多余 import 和旧异步测试；Web 图片解码实现及首帧就绪信号曾失败，强像素校验发现空白截图，已修复并重新完整验证。失败轮次未计作通过。

磁盘不足时只清理本轮拥有的临时平台构建输出，未清用户缓存；最终平台产物、源码与日志保留。ChromeDriver、本轮测试标签页和 localhost server 已关闭。临时文件会随系统清理，长期核对使用仓库证据和后续 CI artifact。

复跑：`python3 blueprint.py validate`、`python3 tool/generator_smoke.py`，以及 [Workbench README](../../examples/workbench_app/README.md) 的真实运行命令。CI 为三 OS × 两种模板的六端构建，并加入 macOS/Windows/Linux 原生及 Chrome 媒体/存储 smoke。远端 CI 本轮未触发，其结果仍为 NOT_RUN。

## 14:12 界面截图补充

应用户要求补拍 macOS Debug 主 App 的实际窗口，原图保存到桌面，未修图副本与 SHA 保存到 [截图 manifest](evidence/2026-09-30-workbench/screenshots/manifest.json)。包含 [文本深色](evidence/2026-09-30-workbench/screenshots/text-dark.png)、[媒体深色](evidence/2026-09-30-workbench/screenshots/media-dark.png)、[媒体明亮](evidence/2026-09-30-workbench/screenshots/media-light.png)、[任务明亮](evidence/2026-09-30-workbench/screenshots/tasks-light.png)。

本次通过 macOS 系统选择器实际导入 repository fixture `gradient.jpg`（1611 字节）及 `landscape.mp4`（21139 字节），UI 显示真实预览和“缩略图已保存”，任务页显示对应完成记录；这补充了上文尚未执行的 macOS 媒体选择器 UI 验收。通过 Tab 移动到任务导航并按 Enter 成功切换；未据此补认 Cmd/Ctrl 快捷键、其他平台选择器或 UI Lab 界面验收。示例待办未添加成功，本次任务截图仅展示真实 IO 作业记录。

## Codex 式固定图标栏与系统标题栏融合

按用户截图保留图标栏与内容侧栏两层结构：工作台使用 64px 固定图标栏、靠上的导航入口和底部设置；设置消费现有主题与密度偏好。窄于 600px 时设置移到顶部，短窗口只滚动导航入口。`koi_ui` 新增纯展示 `navigationTrailing` 槽位，保持页面、router、工作区、文本及媒体会话的拥有者不变。

用户明确要求包含 macOS 红黄绿所在的系统标题栏。因此生成器在确定的 SDK runner 结构中增加 AppKit 窗口桥接，App 将当前主题背景与明暗外观同步到 NSWindow，保留原生按钮和标题栏拖动，并预留原生标题栏高度。未知 runner 结构会明确失败，全部输入验证后才写入；未引入额外窗口管理插件。Windows/Linux 的原生标题栏融合尚未实现及运行，其他平台不调用 macOS 通道。

- 最终 `python3 blueprint.py validate`：PASS，**86.51%，3194/3692 行**；Workbench 62 项 VM 行为通过。
- 定向 UI 测试通过：320、600、1024、1440 宽度、200% 字号、短窗口底部定位、明暗背景一致、设置菜单的 Enter/Escape、焦点恢复与一次激活；UI Lab 的底部设置切换主题和密度。
- 新窗口桥接的主题参数、安全区域、逆序返回、销毁及不可用宿主测试通过；Python 原生配置 4 项通过。
- 真实 macOS Debug 构建与运行 PASS：实际点击底部齿轮后菜单向上展开，Escape 关闭；从菜单切换深色后原生系统标题栏同步变色，文本与媒体视图正常切换，已有中文资料和素材仍可用。
- 新 workbench 项目与 workbench→workbench 递归生成 PASS，覆盖 macos/web、改名和中文输出路径；逐份核对窗口桥接只注册一次。

原始桌面截图的未修改副本：[明亮文本](evidence/2026-09-30-workbench/navigation-rail/text-light.png)、[深色媒体](evidence/2026-09-30-workbench/navigation-rail/media-dark.png)。[本次 manifest](evidence/2026-09-30-workbench/navigation-rail/manifest.json) 保存源码 SHA、截图 SHA、三个区域的颜色采样与完整门禁/生成日志。截图显示真实 Debug 宿主；本次未复跑 Android、iOS、Web 构建或 Windows/Linux/Safari 运行，不能据此前结果补认本次平台验收。

## 页面历史与红黄绿同行的原生工具栏

按用户对位置的修正，macOS 使用原生 `NSToolbar` 将后退、前进和标题放到红黄绿右侧同一行，原生保存操作也接入工作区。宽窗口移除重复的 Flutter 标题区；窄窗口保留抽屉及详情入口。系统标题栏和固定图标栏仍跟随同一个主题背景。其他平台保留 Flutter 历史控件与统一会话。

bootstrap 拥有页面历史，记录三个视图的 URI 和资料/素材选择，最多 100 条，随会话结束释放。后退和前进恢复对应选择；保存、输入、任务进度与 resize 不新增访问记录。返回后打开新内容截断前进记录，已删除内容跳过。编辑控制器、router、工作区和播放器保持稳定；原生窗口仅消费不可变状态与命令回调。

| 本轮验证 | 结果 |
| --- | --- |
| 完整 `python3 blueprint.py validate` | PASS，手写覆盖率 **87.15%，3390/3890 行** |
| Workbench 行为与浏览器存储门禁 | 72 项 VM、8 项 Chrome 行为通过 |
| UI 与生命周期回归 | 320/600/1024/1440、200% 字号、按钮禁用及一次激活、历史重放、编辑/播放身份、销毁和失效宿主回退通过 |
| macOS 原生桥接 | 主题、原生工具栏状态、命令回调、迟到返回与销毁回归通过；实际 Debug 构建 PASS |
| macOS 实际按钮与外观 | PASS：原生后退恢复媒体选择，前进恢复中文资料；禁用状态更新；切换明亮后标题栏与图标栏同色；zoom 后资料保留 |
| 新 workbench 与递归 workbench | PASS：macos/web、改名和中文路径，生成及分析通过；逐份核对身份替换后的源码、素材字节和唯一原生工具栏注册 |

最终未修改的实际窗口截图：[native-text-light.png](evidence/2026-09-30-workbench/page-history/native-text-light.png)。[manifest](evidence/2026-09-30-workbench/page-history/manifest.json) 保存截图、完整门禁、macOS 构建及生成日志的 SHA；运行宿主源码和原生配置在截图后再次核对。`page-history` 中早期三个截图是按钮位于系统标题栏下面的旧方案，已标为 superseded，不作为最终位置证据。

Cmd+[ / Cmd+] 及非 macOS Alt+方向键已有 Widget 回归；真实 macOS 快捷键激活本轮未确认。本次未重新构建 Android、iOS、Web，未完成 Windows/Linux 原生工具栏与 Safari 运行；这些项仍为 NOT_RUN，不能据本轮 macOS 或此前平台结果补认。

## 顶部与侧栏同色、圆角内容面板

按用户的新截图将顶部、固定图标栏和资料侧栏归为同一外壳底色，主体与详情使用另一层内容底色。新增 `chromeBackground` 与 `contentBackground` 语义 token，保留原 `panelBackground` 和构造接口兼容性；普通 Material 宿主从 ColorScheme 回退。明亮主题为灰白外壳与暖白内容，深色主题为深绿外壳与稍亮的内容。

主区和详情共同放在一个 24px 圆角、8px 外边距的 Material 面板中，边框使用弱边框色并真实裁剪子内容。资料侧栏使用 Material 背景，以保留 ListTile 的选中及点击反馈；详情调整仍在内容面板内部。原生标题栏同步外壳 token，保持红黄绿右侧的真实历史控件；没有新增路由、provider 或播放器拥有者。

定向组件 16 项及工作台展示/窗口桥接 22 项通过，包含 320/600/1024/1440、200% 字号、明暗区分、抽屉、面板调整、导航、编辑/播放身份保持及释放。macOS 实际 Debug 构建通过；真实窗口显示正确中文、圆角外沿与主题同步，切换深色再恢复明亮后资料保持不变。新建改名的 macos/web 工作台与 workbench→workbench 递归生成及分析通过，逐字核对配色/圆角源码、原生桥接和素材字节。

实际原图未修图：[明亮](evidence/2026-09-30-workbench/content-surface/text-light.png)、[深色](evidence/2026-09-30-workbench/content-surface/text-dark.png)。截图采样中原生标题栏与图标栏 RGB 完全一致，资料侧栏最多差 1 个 RGB 步长；主体与详情一致且与外壳有明确色差，见 [颜色采样](evidence/2026-09-30-workbench/content-surface/surface-colors.json)。源码、原图和日志证据位于同一目录。

最终完整 `python3 blueprint.py validate`：PASS，手写覆盖率 **87.21%，3408/3908 行**，Workbench 72 项 VM 与 8 项 Chrome 存储行为通过。[本轮 manifest](evidence/2026-09-30-workbench/content-surface/manifest.json) 保存完整门禁、构建、生成、原图与源码核对记录。

本轮其他平台构建与真实运行为 NOT_RUN；模板生成 macos/web 不代表对应平台构建或运行。首次回归发现 ColoredBox 会遮住侧栏的 Material ink 反馈，已替换为 Material 并重新通过；失败轮次未计入最终通过结果。

## 参照 Codex 弱化分割线

只读检查本机 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 中 Codex 的打包 CSS，发现 border-light 使用明亮黑色/深色白色的 `0d` alpha（约 5.1%），border-subtle 引用该弱边框，主内容区边框宽度引用 hairline。选取的样式定义、资源路径与 SHA 保存到 [本机样式核对](evidence/2026-09-30-workbench/subtle-dividers/codex-style-reference.json)。这是当前客户端打包资源的证据，未据此断言每处侧栏具体使用哪个 token，或将它视为公开源码仓库。

工作台结构边线改用 onSurface 的 6% 透明度。两条可调整面板的默认全高线隐藏，保留 12px 全高命中区；鼠标悬停显示 48px 短拖动条，键盘焦点及拖动期间显示品牌色，收起有 120ms 过渡。内容外沿和图标栏分隔线使用同一弱结构色，继续通过底色与留白表达区域。

组件 16 项、工作台展示 16 项定向行为通过，覆盖鼠标进入/离开、键盘焦点、拖动和方向键、尺寸边界、200% 字号及文本/播放器身份保持。首次悬停测试发现 FocusableActionDetector 的 hover 提示受输入高亮模式影响，已改为独立 MouseRegion 并复验通过。实际 macOS Debug 构建 PASS：拖动资料侧栏后边界移动，恢复原宽度后中文资料仍显示；切换深色再恢复明亮，默认长线保持隐藏。截图原图未修改：[明亮](evidence/2026-09-30-workbench/subtle-dividers/text-light.png)、[深色](evidence/2026-09-30-workbench/subtle-dividers/text-dark.png)。

完整 `python3 blueprint.py validate`：PASS，手写覆盖率 **87.23%，3422/3923 行**；Workbench 72 项 VM 与 8 项 Chrome 存储行为通过。[manifest](evidence/2026-09-30-workbench/subtle-dividers/manifest.json) 保存日志、截图、运行源码核对及基线差异。本轮其他平台构建与真实运行为 NOT_RUN；未复跑新项目生成，生成器未修改，共享 UI 源仍由模板直接复制。

## 资料侧栏纳入内容面板

资料标题、搜索和列表属于内容区，现与主体及详情一起放入同一个 24px 圆角、8px 外边距的 Material 面板。只有顶部标题栏和固定图标栏使用 `chromeBackground`；资料侧栏、主体及详情使用 `contentBackground`，两条可调整分隔条都在圆角面板内部。窄窗口的资料抽屉也使用内容底色。公共 token 注释、组件说明和 UI 架构契约已同步；本节记录当前区域归属，此前截图保留为历史验证。

组件 16 项和工作台展示 16 项定向测试 PASS，覆盖列表及详情处于同一裁剪面板、导航栏位于面板外、窄窗口抽屉底色、320/600/1024/1440 宽度及 200% 字号，并复验 resize、导航切换后的编辑与播放身份。完整 `python3 blueprint.py validate` PASS，手写覆盖率 **87.23%，3423/3924 行**；Workbench 72 项 VM 与 8 项 Chrome 存储行为通过。

macOS 实际 Debug 构建与运行 PASS：资料列表、编辑区和详情显示在同一圆角内容面板中，媒体分类侧栏也位于内容面板内部；切换深色并恢复明亮后，中文资料仍选中，保持 32 字、版本 1、已保存。原生标题栏继续位于红黄绿同一行。运行宿主与当前共享 UI 源码 SHA 已核对一致，工作区会话实现未改变。

实际窗口原图未修改：[深色](evidence/2026-09-30-workbench/sidebar-content/text-dark.png)、[明亮](evidence/2026-09-30-workbench/sidebar-content/text-light.png)。[manifest](evidence/2026-09-30-workbench/sidebar-content/manifest.json) 保存源码、日志、截图及本轮基线差异。首轮完整门禁因证据目录中的 Dart 基线副本被分析器扫描而失败，已将副本保留为 `.dart.txt` 并重新通过，未扩大任何排除范围。

本轮其他平台构建与真实运行为 NOT_RUN；未复跑新项目或递归生成，生成器未修改，共享 UI 源由模板直接复制。Chrome 存储测试不代表 Web 界面或 Safari 运行验收。
