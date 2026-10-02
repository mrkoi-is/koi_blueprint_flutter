# 从蓝图创建项目

## 输入与前提

需要项目名（snake_case）、目标目录、组织标识和目标平台。平台可选 `web,android,ios,macos,windows,linux`；不指定平台时生成六端 runner。使用 Python 3.11+ 和与 `.fvmrc` 匹配的 Flutter SDK。Windows 将下列命令的 `python3` 换为 `py -3`。

```sh
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web,macos --dry-run
python3 blueprint.py create field_notes --output ../field_notes --org com.example --platforms web,macos
python3 blueprint.py create studio --output ../studio --org com.example --template workbench --platforms web,macos
```

非空目标、符号链接目标和名称冲突会被拒绝。创建在独立临时目录装配、解析依赖和生成源码，成功后才交付目标目录；不覆盖已有项目。`create --dry-run` 检查输入和展示配置，不运行 SDK、依赖解析或完整配方安装验证。

`--template minimal|workbench` 默认 minimal。活动成员从 App、`koi_core`、`koi_ui` 开始。两种模板默认具备主题、en/zh/zh_Hant 本地化、错误接线和来源信息；minimal 不默认引入认证、网络、文件、媒体或数据库插件。workbench 提供文本资料、图片/视频素材、待办、导入任务与会话存储。其他能力按需安装，保留原有 App 的装配与 router。

工作台使用 SDK 生成 runner，再合并平台配置。macOS 加入用户选择文件的只读权限并保留其他 entitlement；未知结构报错。当前沿用 Flutter 3.47.2 的 Android 24、iOS 15、macOS 12 下限。Linux 工作台需要 `libmpv-dev mpv libepoxy-dev` 及 Flutter GTK 构建依赖。

## 用配置创建

把以下内容保存为自己的 `blueprint.local.json`，然后从源蓝图执行创建命令。配置 schema 当前为 1；未知字段会报错。CLI 与配置同时指定 template、platforms 或 org 时必须一致，不会静默覆盖。

```json
{
  "schema": 1,
  "template": "minimal",
  "org": "com.example",
  "platforms": ["web", "macos"],
  "locales": ["en", "zh", "zh_Hant"],
  "capabilities": ["diagnostics", "settings", "images", "typed-assets"],
  "brand": {"displayName": "锦鲤笔记"},
  "buildProfiles": {
    "web-local": {
      "platform": "web", "arch": "web", "mode": "release",
      "channel": "local", "format": "zip"
    },
    "mac-local": {
      "platform": "macos", "arch": "arm64", "mode": "release",
      "channel": "local", "format": "dmg", "codesign": false
    }
  }
}
```

```sh
python3 blueprint.py create field_notes --output ../field_notes --config blueprint.local.json --dry-run
python3 blueprint.py create field_notes --output ../field_notes --config blueprint.local.json
```

`images` 自动安装其 `network` 依赖。依赖按目录中的顺序解析，来源只取蓝图内置受测配方；`capability list` 的 status 字段与生成项目/目标平台验证日志一起判断完成度。`locales` 省略时使用默认三种语言；目前显式指定时也要求完整的 en/zh/zh_Hant 组合，尚不支持通过删项裁剪翻译。

显示名称同步 App 文案、Android label、Apple bundle/window/menu、Windows/Linux window 和 Web manifest/title，保留包名、bundle identifier 与可执行文件身份。需要图标时，在 brand 中加入 `iconForeground`（相对于配置文件的 PNG 或自包含 SVG 路径）和 `iconBackground`（例如 `#315C80`）；生成器自动加入 branding 能力，需要 ImageMagick 7.1–7.x。首次创建可替换 SDK 默认 runner 图标；已有工程的未受管图标默认拒绝覆盖。资源与图标的输入/输出摘要、限制见 [资源与打包](engineering/assets-and-packaging.md)。

## 首次运行与增装能力

```sh
cd ../field_notes
# 生成器不复制 SDK：安装 .fvmrc 指定 SDK，或设置 FLUTTER_BIN。
python3 blueprint.py doctor --purpose run
python3 blueprint.py devices
python3 blueprint.py run --app apps/field_notes_app --device chrome
# 退出运行后：
python3 blueprint.py capability list --app apps/field_notes_app
python3 blueprint.py capability add database --app apps/field_notes_app --dry-run
python3 blueprint.py capability add database --app apps/field_notes_app
python3 blueprint.py doctor --purpose validate
python3 blueprint.py validate
```

`capability add ID` 每次选择一个能力并递归安装其依赖；`--config` 接受同一 schema 的配置。配置中的 capabilities 若非空，必须包含这次 ID。只有 `home-widget` 当前接受 `capabilityOptions` 的 `appGroup` 字段，其他能力不接受任意参数。平台及模板限制由目录检查，directory-index/task-history/bulk-selection 仅适用于 workbench。

安装会在隔离 workspace 解析依赖和运行生成，随后以一次文件事务提交配方、原生配置、清单、基线和根锁文件；提交前核对旧内容，失败时回滚本次仍拥有的修改。相同版本/配置且文件未改的重复安装无修改；版本/配置不同、受管 registry、原生接线或配方文件被编辑时拒绝覆盖，并提示先看升级报告。自有能力登记在 App 的 `app_capabilities.dart`，不直接修改生成的 `installed_capabilities.dart`。不要让多个进程同时更改同一根锁文件或运行代码生成。

网络能力页面可直接输入 HTTP(S) 服务地址，提交后连接；未配置时不隐式连接服务或启动服务器。已连接时可更换服务，切换前等待旧任务和资源清理，也可返回保留当前查询。`NETWORK_LAB_URL` 编译常量只提供初始值；需要预填时从 App 目录使用固定 SDK wrapper（当前 blueprint run 不透传 dart-define）：

```sh
cd apps/field_notes_app
../../tool/flutterw run -d chrome --dart-define=NETWORK_LAB_URL=http://127.0.0.1:8765/
# 退出 App 后，独立启动受控 HTTP fixture 并测试已安装的网络/图像能力：
python3 tool/run_http_smoke.py --flutter ../../tool/flutterw
cd ../..
```

该地址只是本机受控服务示例；运行 App 前先启动自己的测试服务，设备端换为实际可达地址。HTTP smoke 脚本自行启动/终止临时端口 fixture；network 单独安装运行 5 个真实场景（含地址输入→连接→搜索），加入 images 后增加图像场景。普通 validate 的成员测试跳过需要该服务的 HTTP 组，因此还要单独执行这条 smoke 命令。图片来源页可以单独输入 URL。网络与图片页面、状态和导航标题使用宿主英/简/繁 ARB，切换语言保留页面会话与布局。

Chrome 运行要求生成 Web runner；macOS 将 device 改为 macos，手机使用 devices 返回的 ID。validate 只在活动成员存在浏览器测试时要求 Chrome，只在存在 API Web 冒烟入口时要求 Node。默认 minimal 不要求这两项；workbench 和安装了浏览器测试的能力要求 Chrome。

## 构建和打包

```sh
python3 blueprint.py build --app apps/field_notes_app --profile web-local
python3 blueprint.py package --app apps/field_notes_app --profile web-local
python3 blueprint.py build --app apps/field_notes_app --profile mac-local
python3 blueprint.py package --app apps/field_notes_app --profile mac-local
```

profile 从生成项目 `blueprint.json` 的 configuration.buildProfiles 读取，`--profile` 与 `--platforms` 互斥。也可直接 `build --app ... --platforms web,macos`，分别生成 `web-release` 和 `macos-release` 默认 profile；随后用该名称 package。构建先以严格锁文件解析准备插件，Apple 目标还通过 Flutter `--config-only` 完成 CocoaPods/原生工程接线，再冻结包含 Podfile.lock、Xcode 工程与 workspace 的源码身份；正式构建使用 `--no-pub`，构建期间输入再变化即失败。清单记录准备阶段变更、实际架构、源码/锁文件/配置摘要和产物摘要。成功后 CLI 输出精简 buildInfo（版本、构建号、source、channel、platform、architecture）和 manifest 路径，完整清单留在文件中。

| 平台 | 当前默认架构 | 打包格式与执行边界 |
| --- | --- | --- |
| Web | web | zip；构建不等于浏览器交互通过 |
| Android | arm64-v8a | apk；实际检查全部 native library ABI |
| iOS | arm64 | app；无签名构建可记录，package 要求签名 device build |
| macOS | arm64 | dmg；本机 hdiutil；无签名配置可将 universal 二进制裁为指定架构并记录临时签名命令 |
| Windows | x64 | exe；匹配架构 Windows host + Inno Setup |
| Linux | x64 | deb 或 AppImage；Linux host + 对应打包工具 |

mode 可选 debug/profile/release，默认 release；channel 默认 local。其他允许架构由 CLI 配置校验，不表示已经验收。Windows 使用当前固定 Flutter 的宿主架构构建；已签名 macOS universal 产物不会被工具静默裁剪重签，需先配置 Xcode 的目标架构。

构建清单位于生成 App 的 `apps/<app>/build/blueprint/<profile>.json`；包和 package-manifest 位于 `apps/<app>/build/packages/<profile>/`。打包要求清单为 PASS 且源码、锁文件、profile、App 身份、实际架构及产物内容仍一致；输出目录已存在会拒绝覆盖。打包前后均核对输入，临时失败产物不会晋升为成功输出。`runtime` 和 `installation` 初始均为 `NOT_RUN`，构建/归档成功不能代替目标机运行、安装、升级或卸载。

使用 `doctor` 查看固定 SDK、所需打包工具/版本以及已装能力的依赖、原生动态库加载和 Web 资产摘要。它是诊断输出：`INCOMPLETE`/`NOT_RUN` 要看具体原因，不能只用 doctor 命令退出码推断六端通过。工具安装变量和精确限制见 [资源与打包](engineering/assets-and-packaging.md)，目标端验收见 [平台验收](platform-acceptance.md)。

## 元数据与只读升级

根 `pubspec.yaml` 是 workspace 成员唯一来源，各成员使用 `resolution: workspace`。配置 schema 1 与生成元数据 schema 2 是不同协议；`blueprint.json` schema 2 保存身份、来源、配置、能力清单、受管文件及基线，根锁文件固定解析结果。生成项目保留独立工具和只读配方参照，源仓研究/历史验收不继承。

```sh
python3 blueprint.py upgrade-report --app apps/field_notes_app --source ../koi_blueprint_flutter
```

报告把生成时基线、当前本地文件、当前上游来源分为 upstreamChanges/localChanges/conflicts/alreadyApplied/unchanged；`alreadyApplied` 表示本地文件已与当前上游内容一致。报告还列出新能力和人工迁移说明；只输出 JSON，不写项目、不自动合并、不升级依赖。schema 1 或缺少基线的旧工程可读取，但只得到人工迁移说明，不能直接 capability add。现有项目先人工接入 schema 2 装配和基线，再验证；不要通过改一个 schema 数字伪造迁移完成。下游已有业务改动仍由项目维护者逐项审阅迁移。

逐项处理方式见 [下游工程只读升级指南](upgrade-guide.md)。

## 新增业务功能

```sh
python3 blueprint.py feature apps/field_notes_app welcome --kind presentation
python3 blueprint.py feature apps/field_notes_app catalog --kind api
python3 blueprint.py feature apps/field_notes_app drafts --kind local
python3 blueprint.py module reporting --workspace .
```

presentation 生成无数据源页面，api 生成仓库驱动的分页/搜索骨架，local 生成本地数据与业务状态。脚手架后仍需完成业务字段、宿主导航、依赖 override 和场景测试；示例替身不代表真实后端。新增共享包按 [add-shared-package](../.agents/skills/add-shared-package/SKILL.md) 完成目录、pubspec、workspace 登记和测试。
