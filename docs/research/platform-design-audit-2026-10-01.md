# 平台设计规范审核与迭代

日期：2026-10-01。对象：当前 Koi Flutter 蓝图工作树的 `koi_ui`、UI Lab、工作台文本/媒体/任务流程和模板继承。保留已有未提交工作，修改前对 130 个相关文件记录了哈希与副本，见 [基线](evidence/2026-10-01-platform-design/baseline.json)。

## 目标与审核依据

用户目标是让蓝图先具备稳定、精致的界面骨架，使派生 App 直接继承可用的标准。本轮保留已确认的统一 chrome、固定图标栏、底部设置及包含资料列表的圆角内容表面，检查平台习惯、文字与状态辨识、触摸/键盘操作和辅助技术语义。

依据为 Apple HIG、Windows/Fluent、Android/Material、Flutter 及 WAI 的一手资料，完整链接与用途在 [sources.json](evidence/2026-10-01-platform-design/sources.json)，长期实现契约更新到 [DESIGN.md](../../DESIGN.md#11-平台规范映射与新增页面门禁)。此前 Codex/AppFlowy 比较是视觉组织参考，本轮不把其截图或未公开实现当作平台标准。

尺寸不混用：Apple 建议的44pt、Windows40epx触摸基线与触摸优化44+4、Android48dp，均保留其平台上下文。Koi comfortable 的48是自身跨端逻辑像素基线；compact面向键盘和精确指针，不宣称是触摸配置。WCAG的对比度规则只用于适用的文字及必要识别线索，不据此加粗所有装饰线。

## 已有优点

共享主题和纯展示组件已经成立；两种密度、明暗主题、320/600/1024/1440与200%文字已有基础测试。后退/前进、窗口按钮、原生标题、工作区会话及播放器的职责分离继续保留。测试证实编辑器普通方向键不会被导航快捷键夺走。

单独展示壳的测试不足以证明完整宿主语义。实际 Chrome 开启 Flutter 无障碍后，左侧导航与资料列表没有导出，最后一个调整滑杆的 DOM 范围扩到了整个 viewport；macOS 工具此前也观察到相似缺失。进一步在含内层 Navigator 的完整 Widget 结构中复现，确认路由的语义屏障会越过面板边界，必须建立明确语义容器。

## 已定位并修复的问题

| 项目 | 之前的证据 | 本轮迭代 | 验证落点 |
| --- | --- | --- | --- |
| 列表选中 | 明/暗选中底色与内容底色仅1.15/1.38对比，作为唯一线索较弱 | 保留浅底色，加3×18起始侧短条；RTL镜像；焦点环独立 | `koi_accessible_theme_test.dart` |
| 表单边界 | 输入框边界使用装饰弱线，输入背景上的对比约1.26/1.66 | 必要输入边框使用outline；结构线仍弱 | 同上，必要线索≥3 |
| 文字配对 | 琥珀色secondary沿用白色onSecondary，明色只有3.109 | 明确前景色后4.957；54个实际文字配对检查≥4.5 | 同上 |
| 导航目标 | 64宽图标栏的destination语义目标仅44高 | 两种密度均保底48高，64栏宽不变 | `koi_platform_layout_test.dart`，直接测rect |
| 分栏目标 | comfortable实际命中12宽，Android guideline失败 | comfortable真实预留48；compact维持12；不覆盖邻控件 | 同上，边缘拖动与相邻点击 |
| RTL调整 | leading面板已镜像到右侧，左拖50却把280缩成230 | 按物理方向修复拖动及方向键；Home/End保持宽度端点 | LTR/RTL × leading/trailing |
| 完整宿主语义 | Chrome实际导出的slider范围1710×859，rail/侧栏缺失；单独壳测试未覆盖嵌套Navigator | 面板与拖柄各自隔离语义；补完整路由根树检查，再核对真实Web DOM | `koi_platform_layout_test.dart`；真实 DOM 前后见 `web-semantics-before.json` / `web-semantics-after.json` |
| 减少动画 | 拖柄装饰过渡固定120ms | 读取系统disableAnimations，减少动态效果时零时长 | 同上，UI Lab新增模拟开关 |
| 菜单与浮层 | 显式label+可见文字被重复朗读；未暴露展开状态 | 名称合并为一次；提供expanded，系统Back先关闭浮层/菜单，下一次才退所属页 | `koi_overlay_accessibility_test.dart` |
| 模态浮层 | 自制透明点击层没有标准屏障；布局未避开软键盘 | ModalBarrier隐藏背后语义；Tab闭环；Escape返回焦点；安全区/键盘避让及滚动，迟到close安全且幂等 | 同上，320×600/200%/300键盘占位 |
| 媒体与待办 | 滑杆、独立复选框用途不明确；媒体选中只靠色；重命名空值静默关闭 | 命名与可读值、选中勾选、完整文件名提示、表单标签和错误反馈 | `workspace_accessibility_test.dart` |
| 删除及小窗口 | 待办删除立即发生；短窗口+键盘下文本和媒体空态溢出 | 明确对象的确认框；取消保留数据；内容可滚动、稳定控制器继续复用 | 同上及原workspace presentation契约 |

comfortable每道分栏区域比compact多36宽，是触摸命中与内容空间之间的显式取舍；视觉拖柄仍为2×48短线。不能用重叠透明区域伪造更大目标。后续若工作区需要更高触摸信息密度，应设计专用面板宽度操作，而不是缩回命中范围。

## 流程与视觉证据

1. **进入桌面工作区**：本轮重新捕获真实macOS生成项目，查看外壳、资料/任务区及原生历史按钮。改善前 [文本页](evidence/2026-10-01-platform-design/before-macos-text.png)、[任务页](evidence/2026-10-01-platform-design/before-macos-tasks.png)。窗口逻辑1710×1007，DPR2，截图包含系统阴影，不能用图片总像素反推控件高度。健康度：布局成立，状态识别与必要输入边界需加强。
2. **选择资料、打开操作面板**：Widget测试验证非颜色选中、单次激活、Tab循环、背景语义屏障和焦点恢复。健康度：已修复，真实读屏宣布仍待逐端运行；真实Web导出的控件结构也独立核对。
3. **重命名、删除、媒体控制**：工作台语义/键盘/小窗口测试覆盖明确反馈与取消路径，缩略图读取失败的独立重试按钮也覆盖100%/200%文字。真实Chrome打开指定待办删除框，确认背景控件不再导出、默认焦点为取消，按Enter后两项待办均保留。健康度：本轮已执行这些路径，不能用它们证明媒体解码或实际读屏宣布。
4. **变更布局/输入能力**：UI Lab可模拟RTL、减少动画、主题、密度、宽度和字号；宿主仍持有会话和控制器。最终Web在Chrome导出三个导航入口、设置、资料列表、正文和详情；两道拖柄实际DOM宽度compact12、comfortable48，ArrowRight将侧栏宽度280变成290，详情仍280。设置菜单展开状态与深色切换实际通过。健康度：自动回归和上述浏览器路径已执行，触摸设备真实手感另验收。
5. **迭代后视觉**：[macOS中等窗口文本页](evidence/2026-10-01-platform-design/after-macos-medium-text.png)，800×600逻辑尺寸、DPR2。截图采于视觉修改之后、最终语义容器补丁之前，只作文本页视觉证据；图片来源和范围见 [screenshots.json](evidence/2026-10-01-platform-design/screenshots.json)。最终Web明暗主题另通过浏览器截图目视核对；没有把旧截图冒充最终原生语义验收。

## 验证与限制

完整 `python3 blueprint.py validate` 已通过，手写Dart覆盖率 **88.55%（3775/4263）**，未扩大排除范围。新增35项行为测试：共享主题7、平台布局15、浮层6、工作台7；另外扩展UI Lab现有测试。两种模板完成本轮生成，最终minimal中的全部koi_ui实现与DESIGN逐字节匹配源文件。workbench运行夹具的4次生成后源码刷新已明确记录，测试数据仅在夹具main中注入，不进入空白模板。

生成工作台的最终Web构建与Chrome上述操作通过；macOS增量产物曾出现App.framework签名失效，在隔离验证项目保留旧产物后干净重建，最终构建与签名校验均通过。命令日志及未执行平台统一记录在 [checks.md](evidence/2026-10-01-platform-design/checks.md)。源码、Widget测试、生成/构建及平台运行分别记录，不把编译等同于操作通过。

未完成：专用高对比主题和系统对比度桥接；VoiceOver/TalkBack/Narrator完整宣布顺序；Windows、Android、iOS、Linux本轮真实触摸/键盘运行；Safari完整流程。以上保留NOT_RUN或未实现。对照平台规范实施不等于宣称完全符合平台所有设计标准。

下一轮验收优先在真实触摸设备检验comfortable面板空间与目标手感，并用三端读屏逐项记录名称、状态和值。
