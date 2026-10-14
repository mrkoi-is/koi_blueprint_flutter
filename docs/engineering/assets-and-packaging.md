# 资源与目标平台打包工具

`tool/blueprint_environment.py` 是 doctor 与打包的同一工具清单。缺失工具、错误宿主或不支持版本直接返回具体原因，不安装工具、不下载 runtime、不写成功产物。工具绝对路径可用环境变量覆盖，执行产物清单记录版本与可执行文件 SHA256。

| 格式/任务 | 工具和参数边界 | 配置变量 |
| --- | --- | --- |
| Windows EXE | Inno Setup 6.3.3–7.x，递归包含已验证 Flutter bundle，用户目录安装，带卸载，不自动运行安装器 | `BLUEPRINT_ISCC` |
| Linux DEB | dpkg-deb / dpkg-shlibdeps >= 1.19、1.x；扫描主程序/engine/plugin ELF 计算系统 Depends；装有 audioplayers 时额外登记 GStreamer 动态插件依赖；`--root-owner-group` 构建归档 | `BLUEPRINT_DPKG_DEB`, `BLUEPRINT_DPKG_SHLIBDEPS` |
| Linux AppImage | 有明确版本/commit 的 linuxdeploy + appimagetool（探测所需CLI）；linuxdeploy 收集 ELF 依赖；audioplayers 插件与 scanner 另行收集、隔离加载验证；显式本地 type-2 runtime，检查输出 ELF/AI magic | `BLUEPRINT_LINUXDEPLOY`, `BLUEPRINT_APPIMAGETOOL`, `BLUEPRINT_APPIMAGE_RUNTIME` |
| macOS DMG | 系统 hdiutil，使用通过验证的 App bundle；检查 UDIF 尾部并执行 `hdiutil verify`，命令进入 manifest | `BLUEPRINT_HDIUTIL` |
| 品牌素材 | ImageMagick >= 7.1、7.x；PNG或自包含SVG前景与独立 `#RRGGBB` 背景 | `BLUEPRINT_MAGICK` |

DEB 将随 App 一起提供的私有 Flutter 库排除于 Debian 包名推断，仍扫描它们引用的系统库；其生成成功不代表所有发行版、桌面环境或安装行为已验收。AppImage runtime 必须预先选择和固定，本工具不触发 appimagetool 的默认联网获取。每份 package manifest 的安装状态初始为 `NOT_RUN`，只有实际目标机安装/升级/卸载记录才能补足该证据。

doctor 根据完整 build profile 推断省略的默认格式。AppImage runtime 与 package 共用 type-2 ELF 标识、实际架构和 SHA256 校验，异机标记 `WRONG_HOST`；打包过程中 runtime 被替换会失败。最终输出必须恰有约定产物：ZIP 逐文件检查条目、大小和解压字节哈希；APK/App 与已验证构建一致；EXE 检查 PE，DEB 检查 ar 格式版本及 control/data 容器，AppImage 检查实际架构。格式检查仍不能替代目标系统安装与启动，任何失败均不晋升 staging 输出。

构建先执行严格锁文件的依赖刷新；Android/macOS/iOS 再运行 Flutter `build --config-only` 完成原生配置，随后冻结来源和锁文件，再执行真正编译。Android 准备命令显式使用 `--pub`，让 Flutter 按 debug/release 模式刷新插件注册器；Flutter 3.47 的 `--no-pub` 会跳过这一步，而普通 `pub get` 产生的开发插件注册器不匹配 release Gradle 依赖。准备后验证锁文件未变，再用 `--no-pub` 真正编译，不把 `integration_test` 加入运行依赖。Android SDK 迁移的 Gradle 文件、首次 CocoaPods 修改的 Podfile.lock、Xcode project/workspace 仍是摘要输入，准备清单逐文件记录修改前后哈希。准备时改写非原生源码、准备失败、冻结后源码或锁文件改变均留下 `FAIL` 清单；不匹配的构建主机保持 `NOT_RUN`。产物内的 `BUILD_SOURCE` 使用准备完成后的摘要。

`generate_assets(app)` 从目标 pubspec 的 `flutter.assets` 字符串列表生成 稳定导出 `lib/shared/assets/app_assets.dart`、实现 `lib/shared/assets/generated/app_assets.dart` 与受管的 `test/typed_assets_test.dart`。测试通过 `AppAssets.all` 和 `rootBundle` 实际加载每项资源，比较生成时记录的原始字节长度（允许合法空文件）；PNG/JPEG/GIF/WebP 还经过 Flutter codec 解码并释放图像与 codec，其它格式只验证加载长度。空清单的加载测试明确跳过，不表示已加载资源。`AppAssets.bundleKey(path, package: 'shared_assets')` 提供跨包键名；生成测试的 import 跟随目标 pubspec 包名。

目录条目遵循 Flutter 的直接文件语义，检查资源缺失、路径逃逸、大小写/生成名称碰撞。`apps/<app>/.blueprint/assets.json` 记录 pubspec、资源与三个输出的摘要；重复运行无修改，常量或测试被用户编辑时整个计划拒绝覆盖。资源改名后重新生成会同步 typed 常量与期望长度；生成实现位于 `generated/`，沿用覆盖率生成目录边界；普通未测手写逻辑仍会失败。该工具不增加运行依赖。

生成加载测试显式运行于 VM：当前锁定 Flutter 的 Chrome 单元测试环境忽略平台消息，且测试服务器不提供构建后的资产 bundle。Web 资源需在真实构建/运行的 App 中验证，不能以此 VM 测试代替 Web 验收。

`apply_brand(app, brand, platforms, source_root=...)` 先临时生成，再以文件事务写入：Android legacy/adaptive icons、Android splash 与 Android 12 splash，Apple AppIcon slots、iOS launch images/background，Windows 多尺寸 ICO，Web普通/maskable icons/favicon，Linux打包图标。它保留透明前景输入并生成独立完成图标；ImageMagick去除时间元数据，保证相同输入重复执行不变。`apps/<app>/.blueprint/brand.json` 保护已有输出。仅新项目 staging 可传 `adopt_runner_assets=True` 替换默认 Flutter runner 素材；已有项目默认保护所有未知/修改过的文件。

品牌工具不负责改依赖或自动注册 pubspec；宿主生成器在统一装配阶段登记 `assets/brand/`，随后调用 typed-assets 生成。平台 runner 必须已经存在。

已实现验证分为 Python适配器/事务行为、当前macOS真实ImageMagick像素尺寸与ICO检查、目标宿主打包执行和安装验收。前两类通过不应替代后两类。当前本地Windows/Linux原生打包执行必须单独记录状态。

依据：[Inno Setup compiler CLI](https://jrsoftware.org/ishelp/topic_compilercmdline.htm)、[dpkg-deb](https://manpages.debian.org/trixie/dpkg/dpkg-deb.1.en.html)、[AppImage工具与固定runtime](https://github.com/AppImage/appimagetool/blob/main/README.md)、[AppDir规范](https://docs.appimage.org/reference/appdir.html)。

`plan_display_name(app, name, platforms)` 是纯计划函数，返回相对路径到 bytes 的变更映射：同步 Android label、Apple bundle/window/menu 名称、Windows window/version-resource 名称、Linux window title 与 Web manifest/title；不改 bundle identifier 或可执行文件身份。宿主将该计划合并到同一生成事务，重复运行无变更。

`capability_doctor(app, capabilities)` 从同一能力目录和锁文件核对依赖版本。它只探测 App 自有构建产物，在隔离进程加载 SQLite 并执行内存 SQL，或加载 mpv 并初始化无输出引擎；报告库 SHA256 和加载搜索目录。Web 数据库资产核对已固定版本、大小和 SHA256，浏览器 worker/SQLite 实际运行仍标记 `NOT_RUN`；异机、设备和未构建平台也保留 `NOT_RUN`。动态库加载通过不代替播放、设备或安装验收。


Linux 目标只有在该 App 的运行依赖声明或已解析插件清单包含 audioplayers 时才增加 GStreamer 检查；不会因为 workspace 锁文件中另一个 App 的依赖触发。doctor 检查 `gstreamer-1.0`、`gstreamer-app-1.0`、`gstreamer-audio-1.0` 的 pkg-config 1.x 元数据，并在子进程真实加载三项运行库、执行 `gst_init_check` 和六项插件工厂实例化。缺少构建模块、库不可加载、插件缺失均 FAIL；非 Linux 宿主明确 NOT_RUN。它是宿主前置依赖检查，不能替代 App 播放验证。

DEB 为该引擎明确加入 `libgstreamer1.0-0`、`libgstreamer-plugins-base1.0-0`、`gstreamer1.0-plugins-base`、`gstreamer1.0-plugins-good`；保留 shlibdeps 推导的版本约束，未安装该引擎的 App 不增加这些包。后两项提供 playbin、autoaudiosink、audiopanorama 等动态插件，不能只声明两个运行库就称依赖完整。

AppImage 从 pkg-config 的 pluginsdir/pluginscannerdir 收集构建宿主已安装的 GStreamer 插件集合及 gst-plugin-scanner，核对架构并交给 linuxdeploy 收集 ELF 依赖。打包前检查 scanner 动态依赖，再在新的进程与隔离插件路径中逐个加载插件，实例化 playbin、audioconvert、audioresample、wavparse、autoaudiosink、audiopanorama；核心库或工厂回退到 AppDir 外即 FAIL。清单记录原始/打包 SHA256、依赖命令和加载证据；缺失、架构错误、加载失败、不完整集合或输入并发改变均不产出 AppImage。AppRun 固定 `GST_PLUGIN_PATH`/`GST_PLUGIN_PATH_1_0`、清空系统插件路径、固定 scanner，并禁用共享 registry 缓存以避免加载宿主旧插件。该流程不下载插件，也不承诺宿主未安装的额外格式解码器；实际 Linux 打包、声音输出与安装仍需要 Linux 宿主验收，当前 macOS 上的适配器回归不替代它。

依据：[audioplayers Linux 的构建模块](https://github.com/bluefireteam/audioplayers/blob/main/packages/audioplayers_linux/linux/CMakeLists.txt)、[实际音频工厂](https://github.com/bluefireteam/audioplayers/blob/main/packages/audioplayers_linux/linux/audio_player.cc)、[GStreamer 的 pkg-config 安装目录](https://github.com/GStreamer/gstreamer/blob/main/subprojects/gstreamer/meson.build)。
