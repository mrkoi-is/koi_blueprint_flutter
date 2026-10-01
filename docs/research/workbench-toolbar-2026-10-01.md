# 工作台单层顶部工具栏迭代

日期：2026-10-01。保留现有工作树；本轮12个受影响既有文件的副本与哈希见 `evidence/2026-10-01-workbench-toolbar/baseline.json`，副本均使用.txt后缀避免被当作工作区可执行源码。

用户截图是600–1023逻辑宽度时的窄窗口桌面布局：保留图标栏，资料/详情改用抽屉。此前原生标题栏已有历史按钮，但Frame为抽屉再生成一行AppBar，造成顶部重复。截图中的IO任务是已取消导入、已处理0字节的记录，和布局模式属于不同状态。

## 最终实现

- 系统标题栏按红黄绿 → 后退/前进 → 资料侧栏 → 标题排列，右侧为详情及保存；AppKit使用SF Symbols `sidebar.left/right`。
- `KoiWorkbenchController` 在纯UI包拥有面板展示命令。宽布局切换内联面板，窄布局切换Scaffold抽屉；没有仓库、路由或媒体依赖。App持有稳定控制器，原生桥接订阅当前可用性和开合状态。
- `showHeader: false` 在所有宽度都不再生成第二行工具栏。桥接确认原生panelToolbar能力后才接管；回退Flutter头栏也采用左右面板轮廓图标，去掉info图标和默认英文navigation menu提示。
- 页面装配通过可选 `detail` Widget决定入口：文本与媒体保留详情，任务正文已展示任务信息，因此任务页不显示详情按钮。回到文本页时原生详情按钮恢复。
- compact回退不再为历史按钮生成额外一行，历史控件与面板按钮处于同一行；极窄原生桌面窗口在底栏旁保留设置入口。
- 移动底栏未强行减高。Flutter Material 3 `NavigationBar` 默认80，系统安全区自动加入一次。测试34底部inset的实际总高为114，不是重复padding；这是Material组件尺寸，并非iOS原生Tab Bar高度。[Flutter高度说明](https://api.flutter.dev/flutter/material/NavigationBar/height.html)

共享接口与布局配方已同步 [DESIGN.md](../../DESIGN.md) 及 [koi_ui README](../../packages/koi_ui/README.md)。生成器维护受测的确定性原生toolbar注入，不手工维护第二份runner；当前生成项目再次生成时沿用这一配置。

## 本轮证据

- 新增5项共享行为测试：320/800/1440下的宿主命令、200%文字、面板隐藏/抽屉开合、编辑控制器保持、页面移除详情、单层回退头栏、底栏inset一次。
- 扩展真实宿主测试，通过平台通道执行侧栏/详情命令、保留草稿和编辑器身份，切任务页同步详情不可用，320宽仍可打开抽屉和设置。
- 平台配置4项Python回归通过，覆盖幂等、SDK键保留、已知结构和未知结构失败。
- 全新隔离workbench项目生成成功；只有main注入一次性中文样本，模板保持空白。macOS/Web release构建及macOS深度签名校验通过。
- macOS800×600真实点击通过：侧栏开、详情开/关、任务导航隐藏详情按钮、原生后退恢复文本与详情入口。记录见 [native-run.json](evidence/2026-10-01-workbench-toolbar/native-run.json)。真实平台样例截图见 [文本页](evidence/2026-10-01-workbench-toolbar/macos-text-toolbar.png) 和 [任务页](evidence/2026-10-01-workbench-toolbar/macos-tasks-toolbar.png)，DPR2、包含窗口阴影，勿将图片像素当作逻辑控件尺寸。
- 完整 `python3 blueprint.py validate` **通过**，手写覆盖率 **88.44%（3901/4411）**，未扩大排除范围。最终结果记录在 `evidence/2026-10-01-workbench-toolbar/validate-final.log`；初次日志保留失败历史，不用于最终通过声明。

本轮没有执行Windows/Linux/iOS/Android真机、VoiceOver完整宣布、Safari或新版回退头栏的真实Web操作。Widget测试、macOS实际点击、Web构建的证据分别成立，不能互相代替。
