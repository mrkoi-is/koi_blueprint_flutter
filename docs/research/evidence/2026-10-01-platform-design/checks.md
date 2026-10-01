# 本轮验证记录

2026-10-01。仅记录本轮执行，旧报告不继承为本轮通过。修改涉及18个源码/测试/规范文件，逐文件前后哈希在 changes.json；另新增本报告与证据。

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| 修改基线 | PASS | baseline.json；130个相关文件副本；保留已有工作树 |
| 定向共享主题/状态 | PASS | 7新测试；主题+既有组件/规范29 tests；54个实际文字配对≥4.5 |
| 定向分栏/导航 | PASS | 15新测试；RTL、真实目标、嵌套Navigator根语义树；合并既有测试37 tests，layout-focused-tests.log |
| 定向浮层 | PASS | 6新测试；模态、Back、焦点、键盘与迟到回调；overlay-focused-tests.log |
| 定向工作台 | PASS | 7新测试+16既有测试；320×600、200%、软键盘、滑杆、删除、真实缩略图读取失败及重试；workspace-focused-tests.log |
| 完整validate | PASS | validate.log；含架构/AI、生成、格式、分析、测试、浏览器桥接覆盖、JS smoke |
| 手写覆盖率 | PASS | 88.55%（3775/4263），目标80%，未扩展排除 |
| 生成workbench | PASS_WITH_FIXTURE_REFRESH | generate-workbench.log；generated-runtime.json明确4个文件刷新；runtime-main.dart.txt注入一次性测试数据 |
| 最终生成minimal | PASS | generate-minimal.log / generated-minimal.json；全部koi_ui实现及DESIGN字节匹配 |
| Web release构建 | PASS | generated-build.log；最终语义修复已包括 |
| macOS release构建 | PASS_CLEAN_REBUILD | 增量产物签名失效后，隔离项目干净重建成功；generated-macos-clean-build.log；codesign-final.log退出0 |
| Chrome实际操作 | PASS_SCOPED | web-semantics-after.json；导航/列表完整导出、真实48/12目标、键盘宽度280→290、主题、删除默认取消 |
| macOS实际运行 | PASS_VISUAL_SCOPED | before/after截图及screenshots.json；最终语义补丁之后原生AX未复验 |
| Android/iOS/Windows/Linux构建及运行 | NOT_RUN | 本轮未执行；自动化中的平台分支不能代替目标宿主 |
| VoiceOver/TalkBack/Narrator | NOT_RUN | Widget语义、DOM/AX工具读取不等于实际读屏宣布 |
| Safari完整流程 | NOT_RUN | 本轮未执行 |

## 证据范围

- 35项新增行为测试及UI Lab现有测试扩展；没有为静态文案另造镜像测试。
- 生成器递归组合、回滚等由完整validate中的既有自动测试覆盖；本轮没有在真实SDK上逐一运行全部递归组合。
- Web验证使用本轮最终生成产物，开启Flutter无障碍后读取实际导出的DOM/AX并执行点击/键盘。没有执行真实媒体解码、录屏或完整浏览器兼容验收。
- macOS截图在800×600逻辑窗口、2倍DPR下采集；包含系统阴影。最终语义修复不改变该文本页外观，但该图片不证明最终原生AX行为。
- 原生连接工具对新夹具App超时，改用只读窗口截图作视觉记录；没有绕过权限去控制原生UI。
- Web构建仍有既有Cupertino字体树摇警告；macOS媒体插件尚未采用Swift Package Manager。均记录为现有工具链提示，本轮未变更依赖。
- 专用高对比主题与系统对比度模式桥接 **未实现**；真实触摸/读屏与Safari保留 **NOT_RUN**，不声称六端完全符合全部平台规范。
