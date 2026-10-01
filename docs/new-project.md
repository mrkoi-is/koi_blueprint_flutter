# 从蓝图创建项目

## 输入与前提

需要项目名（snake_case）、目标目录、组织标识和目标平台。平台可选 `web,android,ios,macos,windows,linux`；仅生成需要的平台。安装与 `.fvmrc` 匹配的 Flutter SDK 和 Python 3.11 或更新版本，优先用项目 wrapper；Windows 命令前缀为 `py -3`。

```sh
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web,macos --dry-run
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web,macos
python3 blueprint.py create studio --output ../studio --org com.example --template workbench --platforms web,macos
```

先检查 dry-run 给出的目标和操作。遇到非空目标或名称冲突时修正输入，不覆盖已有工作。创建结果是独立 workspace，默认 App 路径为 apps/field_notes_app，不包含蓝图认证演示依赖。

`--template minimal|workbench` 默认 `minimal`。两种模板的活动成员均为 App、`koi_core`、`koi_ui`；所有新 App 使用统一明暗主题。minimal 不依赖文件、媒体、存储插件。workbench 提供文本资料、图片/视频素材、待办与真实导入任务；内容存储、平台插件与任务编排留在该 App 内。UI Lab 仅在参照快照中保留。

工作台使用 SDK 生成 runner，再确定性合并平台配置。macOS DebugProfile/Release 加入用户选择文件的只读权限，保留其他键；未知结构报错。沿用 Flutter 3.47.2 默认 Android 24、iOS 15、macOS 12，不下调 SDK 底线。Linux 需安装 `libmpv-dev mpv libepoxy-dev` 及 Flutter 的 GTK 构建依赖。

## 配置的职责

- 根 `pubspec.yaml` 的 `workspace` 是成员清单的唯一来源。每个成员写 `resolution: workspace`。
- `blueprint.json` 保存名称、主 App、平台和 template 元数据，不重复维护成员列表；旧记录缺少 template 时视为 minimal。
- `.fvmrc` 固定 Flutter，`pubspec.lock` 固定依赖解析；生成器版本成组调整。
- 各工具入口和 AI 资产随项目保留；新项目运行不需要作者机器上的其他仓库。
- 源蓝图的研究笔记与历史验证记录不进入生成项目；新项目从自己的验证结果开始记录。

## 首次运行

```sh
cd ../field_notes
python3 blueprint.py validate
python3 blueprint.py build --app apps/field_notes_app --platforms web
```

macOS 构建须在 macOS 主机运行；Windows、Linux、Android、iOS 也应分别在具备对应工具链的主机验证。生成目录不代表六端已经构建通过。只报告实际运行的平台与失败原因。

## 新增功能

```sh
python3 blueprint.py feature apps/field_notes_app welcome --kind presentation
python3 blueprint.py feature apps/field_notes_app catalog --kind api
python3 blueprint.py feature apps/field_notes_app drafts --kind local
python3 blueprint.py module reporting --workspace .
```

`presentation` 用于无数据源的页面，`api` 用于仓库驱动的异步读取，`local` 用于本地数据与业务状态。生成后仍要完成业务字段、宿主导航、真实依赖 override 和场景测试。网络/本地实现的示例替身不能冒充真实后端或持久化。

新增共享包目前按 [add-shared-package](../.agent/skills/add-shared-package/SKILL.md) 手工完成目录、pubspec、workspace 登记和测试。

## 验收与身份替换

检查根名、App 名、包 import、组织标识、平台名称和显示名。不要对整个仓库盲目全局替换；版权/历史记录/参考链接不属于产品身份。新 workspace 应能独立解析依赖、生成源码、测试并构建选定平台。保持模板生成回归覆盖改名、重复名称、非空目标、模块和三类 Feature。
