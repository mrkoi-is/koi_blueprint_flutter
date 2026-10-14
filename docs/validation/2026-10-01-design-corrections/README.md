# DESIGN 整体修正交付记录

日期：2026-10-01。基线：511db23。对应[全仓审核](../../research/design-code-audit-2026-10-01.md)。

## 修改完成

| 审核项 | 修正 |
| --- | --- |
| F01/F02 | koi_ui 的 KoiPanel 统一固定头部、可选搜索、滚动主体；三个侧栏都复用。标题水平12/顶部20，无用途的任务搜索不添加。短高度时头部可独立滚动。 |
| F03 | 两个详情复用同一面板头部与 KoiPropertyRow，统一属性名、属性值、组间距；媒体失败与重试仍独立显示。 |
| F04 | WorkspaceShell 持有稳定 PageStorageBucket；每个侧栏、详情具有独立列表标识，跨导航和抽屉/内联切换恢复滚动。 |
| F05 | empty/error/loading 复用自适应反馈布局，足够空间居中、不足可滚动；大字号重试可达。 |
| F06 | WorkspaceSaveStatus 分别呈现文档 revision 的未保存/已保存与工作区保存中/失败；沿用已有提交和 revision 清理算法，不改变存储语义。原生工具栏下正文反馈仍存在。 |
| F07 | Admin 用共享工作台壳和局部断点，桌面设置固定底部；单主目的地的窄布局没有无用途的底部导航，设置及返回总览位于同一标题栏。主体限制最大宽800。 |
| F08 | Admin 登录去掉固定浅色背景；初始化失败接共享明暗主题和反馈组件，主题上下文正确。 |
| F09/F10 | tonal 的容器与文字采用中性 ColorScheme 配对；rail图标22，compact操作图标18、comfortable20，命中区域仍独立处理。 |
| F11 | 搜索支持清除、焦点恢复、外部值更新及借用 controller；清除一次回调，借用控制器不由组件销毁，清除按钮不撑高紧凑搜索。 |
| F12 | UI Lab 消费同一面板/属性配方；DESIGN、UI架构文档、共享包说明和canonical state-management技能同步；添加真实消费几何、滚动与保存反馈回归。 |

保留主题外壳/面板/正文独立底色，未改历史按钮背景或重建路由/播放器。基本控件仍使用 Flutter Material 和 ThemeData；新增组件是薄的布局组合。

## 已复现并验证的修正

- 三个侧栏标题起点都为(12,20)，视图往返滚动480→480。
- 桌面面板→800宽抽屉→桌面面板恢复滚动，router/preview身份不变。
- 两个详情在200%字号下标题同位置，属性名12、属性值14；有名称/大小/类型/缩略图状态标签。
- 320×300、200%字号，明暗×两种密度下错误/空/加载无溢出；可滚动到重试并激活。
- 保存中继续编辑保持未保存；提交失败保留内容与dirty，重试成功恢复已保存。
- Admin在320/600/1024/1440局部宽度按断点切换，设置底部可达，当前设置页不误选总览；窄布局保留页面标题。
- 搜索清除只发一次空查询回调并恢复输入焦点；外部值更新和控制器拥有者切换安全；compact高度不随清除按钮跳动。

## 验证记录

最终生产源码已冻结并补跑格式、分析、AI与覆盖率检查。完整validate通过后，Admin窄标题栏的最后调整由专项测试与最终覆盖率重新验证。历史审核探针保存于research，断言“偏差存在”不属于修正门禁。

| 项目 | 状态与证据 |
| --- | --- |
| 完整 validate | PASS，含架构、AI资产、生成、格式、分析、成员测试、真实Chrome浏览器门禁、覆盖率与Web编译冒烟；见[validate.log](validate.log) |
| 最终格式/分析/AI | PASS：[final-format.log](final-format.log)、[final-analyze.log](final-analyze.log)、[final-ai.log](final-ai.log) |
| 针对原触发条件的回归 | PASS：[panel-regressions.log](panel-regressions.log)、[admin-layout.log](admin-layout.log) |
| 新生成工程 | 创建workbench（web/macos）并通过分析；冻结前最后几处源码在该临时工程同步后重新分析、跑三项面板回归及两端构建。见[fresh-project.log](fresh-project.log)、[final-generated-checks.log](final-generated-checks.log)、[同步文件记录](final-template-sync.json)。未修改SDK runner或二进制资源。最终56个生产源码文件逐一匹配：[匹配记录](final-production-source-match.json)。 |
| Web/macOS构建 | PASS，见final-generated-checks.log |
| macOS实际运行 | PASS，真实Player/图片/缩略图/存储重开：[macos-runtime.log](macos-runtime.log)、[结构化证据](macos-runtime-evidence.json) |
| 手写覆盖率 | PASS，89.76%（4543/5061），见[final-coverage.log](final-coverage.log)；未采集Web桥接按零覆盖计入，不扩大排除、不降低80%底线 |
| Android/iOS/Windows/Linux本轮构建运行 | NOT_RUN |
| Safari/六端视觉与真实读屏矩阵 | NOT_RUN |

macOS运行冒烟使用隔离素材与应用存储沙箱、真实图片与Player；文件选择器由fixture替代，其原生交互不是本轮验收范围。Chrome门禁证明真实IndexedDB/Blob行为，不代替完整浏览器视觉矩阵。不能把Web/macOS构建成功推广为六端运行成功。

本轮修正、测试与验收记录一并提交到本地 Git；未推送远端。临时生成工程路径记录于[fresh-project.json](fresh-project.json)，日志与修正说明保存在本仓库。
