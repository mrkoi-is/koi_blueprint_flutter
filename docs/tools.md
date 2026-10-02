# 工具清单

从 workspace 根目录执行。首选 `python3 blueprint.py`；Windows 使用 `py -3`。Python 3.11+、SDK 版本与选择规则见 [创建项目](new-project.md)。辅助脚本不是另一套流程：日常门禁统一委托 blueprint。源仓库的研究与验收历史不会复制到生成项目。

## 主入口

| 命令 | 用途与边界 |
| --- | --- |
| `python3 blueprint.py create NAME --output PATH --org com.example` | 默认 minimal；`--template workbench` 增加工作台；`--platforms` 选择 runner，不指定时六端；`--dry-run` 只检查输入和展示计划 |
| `python3 blueprint.py create NAME --output PATH --config CONFIG` | schema 1 JSON 指定模板、平台、能力、品牌和构建 profile；与显式 CLI 冲突时报错；示例见 [创建项目](new-project.md) |
| `python3 blueprint.py capability list --app PATH` | JSON 列出内置能力、依赖、模板/平台、源码状态与是否已安装 |
| `python3 blueprint.py capability add ID --app PATH --dry-run` | 展示单项能力及依赖的文件计划；去掉 dry-run 后 staging 解析/生成并事务提交；可传 `--config CONFIG` |
| `python3 blueprint.py feature PATH NAME --kind presentation\|api\|local` | 从受测源码生成 Feature、依赖和测试；宿主注入、导航与真实业务仍需接入 |
| `python3 blueprint.py module NAME --workspace .` | 创建独立业务 module；宿主显式注册 |
| `python3 blueprint.py run --app PATH --device ID` | 使用固定 SDK 启动活动成员；先用 `devices` 获取 ID |
| `python3 blueprint.py devices` | 列出设备 |
| `python3 blueprint.py doctor --purpose run` | SDK、profile 打包工具与版本、已装能力依赖、App 动态库实际加载、Web 资产摘要；`--purpose validate` 另检查活动测试需要的 Chrome/Node |
| `python3 blueprint.py validate` | 严格锁文件、源仓模板资产、生成、格式、架构、AI、分析、测试、浏览器与覆盖率；目标构建另做 |
| `python3 blueprint.py build --app PATH --platforms web,macos` | 为选定平台创建默认 `<platform>-release` profile 构建清单；要求已生成 runner 和匹配工具链 |
| `python3 blueprint.py build --app PATH --profile NAME` | 读取生成元数据中的 buildProfiles；与 platforms 互斥；Apple 目标先准备原生依赖再冻结身份，记录源码、lock、profile、实际架构与产物摘要 |
| `python3 blueprint.py package --app PATH --profile NAME` | 只打包输入仍匹配的成功构建；支持 Web zip、Android apk、iOS app、macOS dmg、Windows exe、Linux deb/AppImage；不安装或发布 |
| `python3 blueprint.py upgrade-report --app PATH --source SOURCE` | 只读比较基线/本地/上游，输出 JSON 与人工迁移说明；不写项目、不合并、不解析依赖 |

每条子命令的参数含义以 `--help` 为准。升级命令是 `upgrade-report`，没有 upgrade/apply 子命令。`run` 当前只接受 app/device，需编译常量时从 App 目录直接使用固定 SDK wrapper，见 [创建项目](new-project.md)。

能力安装只接受 schema 2 主 App，来源仅为内置配方及其继承参照。相同版本/配置的重复安装先核对既有输出摘要；发现用户修改、未知目标文件或 registry/native wiring 变化时拒绝覆盖。安装事务包含根锁文件和受管基线，避免并发 pub get/codegen；受管 registry 之外的自有接线放到 App 的 app_capabilities 文件。schema 1 旧工程只能得到人工迁移报告，不能通过修改 schema 数字绕过缺少的装配与基线。

构建先严格 pub get 刷新插件登记，再以 no-pub 构建；成功时打印版本、构建号、source、channel、platform、architecture 和 manifest 路径，完整清单保留在文件。package 在打包前后核对源与产物。清单位于生成 App 的 `apps/<app>/build/blueprint/<profile>.json` 和 `apps/<app>/build/packages/<profile>/package-manifest.json`，已有包目录拒绝覆盖。实际运行与安装初始为 NOT_RUN。无签名 iOS 可构建但不产生可安装 app 包；Windows/Linux 必须匹配宿主，AppImage 需要显式提供固定 runtime 文件。

doctor 的 JSON 区分工具 AVAILABLE、能力依赖 MATCH、库 LOADABLE、Web VERIFIED_ASSETS 和 NOT_RUN/INCOMPLETE/FAIL。SQLite 会执行内存 SQL，mpv 会初始化无输出引擎；这些检查不证明设备、浏览器 worker 或媒体播放通过。诊断命令退出码不代表六端验收状态，应阅读报告和对应目标日志。详细工具版本、环境变量和图标/资源限制见 [资源与打包](engineering/assets-and-packaging.md)。

## 分项门禁与兼容入口

| `check` phase / Make 目标 | 行为 |
| --- | --- |
| `bootstrap` | 严格锁文件解析 |
| `generate`、`generate-check` | 两者都重建未入库的 Dart part；检验生成能完整运行，会写生成文件，不是只读 drift 检查 |
| `format`、`format-check` | 前者修正格式，后者只读检查 |
| `architecture`、`ai` | AST 架构边界；AI 资产、引用、维护文档可发现性 |
| `templates` | 两种模板的继承资产投影，排除源仓历史后检查链接；源仓 validate 自动执行 |
| `analyze`、`test`、`browser` | fatal-infos 分析；成员及工具测试；活动成员 test/browser 的真实 Chrome 测试 |
| `coverage` | 合并手写覆盖率，未采集可执行源码按零命中计入；默认 80% |

`make validate` 与 `make precommit` 都运行完整 validate。Melos 包装见 [MELOS_USAGE.md](../MELOS_USAGE.md)。

| 文件 | 用途 |
| --- | --- |
| [scripts/validate_workspace.sh](../scripts/validate_workspace.sh) | 本地 validate 兼容包装；CI 直接调用 Python 主入口 |
| [scripts/check_generated.sh](../scripts/check_generated.sh) | `check generate-check` 兼容包装 |
| [scripts/check_coverage.sh](../scripts/check_coverage.sh) | `check coverage` 兼容包装，可传 `--coverage-min` |
| [scripts/create_feature.py](../scripts/create_feature.py) | 旧入口 `PATH NAME` 默认 api；支持显式 `--kind local`，`--presentation-only` 等价 presentation；两种类型参数不可混用 |
| [tool/flutterw](../tool/flutterw)、[tool/dartw](../tool/dartw)、[tool/melos](../tool/melos) | SDK/命令兼容包装；日常优先使用 blueprint，避免多个入口的 SDK 选择差异 |

## 维护与集成工具

| 文件与运行方式 | 用途 |
| --- | --- |
| [tool/generator_smoke.py](../tool/generator_smoke.py)，`python3 tool/generator_smoke.py` | 临时目录真实生成、两个模板及四种递归组合、三类 Feature、module 的分析/测试/完整验证；比 templates 更重，单独执行 |
| [tool/check_template_assets.py](../tool/check_template_assets.py)，`python3 tool/check_template_assets.py` | 无 SDK 的继承资产门禁；blueprint check templates 委托它 |
| [tool/check_ai_assets.py](../tool/check_ai_assets.py)，`python3 tool/check_ai_assets.py` | AI 资产与引用检查，等价 check ai 的底层入口 |
| [tool/check_architecture.dart](../tool/check_architecture.dart) / [AST 实现说明](../tool/architecture/README.md) | 架构检查底层入口，通常用 check architecture |
| [tool/check_coverage_sources.dart](../tool/check_coverage_sources.dart)、[tool/include_browser_coverage.dart](../tool/include_browser_coverage.dart) | coverage 内部审计：遗漏源码、浏览器零命中行；通过 check coverage 使用 |
| [tool/blueprint_config.py](../tool/blueprint_config.py)、[能力目录](../tool/capabilities/catalog.json) | JSON 输入、平台/profile 约束、内置能力依赖与受测配方来源；不根据任意远程地址安装 |
| [tool/blueprint_capabilities.py](../tool/blueprint_capabilities.py)、[tool/blueprint_provenance.py](../tool/blueprint_provenance.py) | 安装计划/事务、文件所有权与来源基线、只读三方升级报告；通过主 CLI 使用 |
| [tool/blueprint_build.py](../tool/blueprint_build.py)、[tool/blueprint_packagers.py](../tool/blueprint_packagers.py) | 构建/产物身份与精确架构校验、匹配宿主的打包适配器；PASS 不代表安装/运行 |
| [tool/blueprint_environment.py](../tool/blueprint_environment.py)、[tool/blueprint_capability_doctor.py](../tool/blueprint_capability_doctor.py) | doctor 和 packager 共用工具身份/版本；能力依赖及实际库加载和 Web 资产校验 |
| [tool/blueprint_assets.py](../tool/blueprint_assets.py)、[tool/blueprint_branding.py](../tool/blueprint_branding.py)、[tool/blueprint_display_name.py](../tool/blueprint_display_name.py) | typed-assets、品牌素材与六端显示名称计划；摘要保护未知/被修改输出；由 create/capability 工具调用 |
| [tool/platform_configuration.py](../tool/platform_configuration.py)、[tool/platform_capabilities.py](../tool/platform_capabilities.py)、[tool/device_capabilities.py](../tool/device_capabilities.py) | workbench 与可选能力原生配置计划，由统一安装事务合并，不是独立发布入口 |
| [tool/create_media_fixtures.py](../tool/create_media_fixtures.py)，`python3 tool/create_media_fixtures.py` | 重新生成并覆盖已登记的合成图片/视频集成素材，需要 ffmpeg 与 ffprobe；仅在维护 fixture 时执行，不读用户素材库 |
| [tool/platform_evidence.py](../tool/platform_evidence.py)，`python3 tool/platform_evidence.py --output PATH` | 记录源码指纹，不执行也不宣称平台通过；日志与 NOT_RUN 按 [平台验收](platform-acceptance.md) 另记 |

Python 工具测试位于 `scripts/tests` 与 `tool/tests`，在 check test 中执行；Dart 工具行为测试也纳入同一阶段。修改 Skill 时另读 [维护契约](../.agents/skills/GOVERNANCE.md)。
