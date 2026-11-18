# 测试与验证策略

## 分层行为

- domain/core：模型、不变量、错误转换与序列化。
- repository/data：fixture/替身驱动的成功、失败与数据映射；真实 IO 只在隔离集成测试中使用。
- provider/application：状态变化、loading/error/empty、重试、并发逆序、销毁和资源拥有者。
- presentation：渲染、语义化动作、尺寸与可访问交互；props 和 provider 容器分别测试。
- router/bootstrap：宿主到页面可达、参数解析、注入完整、redirect、router 稳定与释放。
- modules：重复 ID/路由拒绝、会话切换、异步旧结果隔离、模块资源释放而共享服务存活。
- generator：干净目标生成、改名、三类 Feature、module、非法参数、冲突目标和跨平台命令路径。

## 门禁

统一入口 `python3 blueprint.py validate`。默认手写代码合并行覆盖率不低于 **80%**，可用 `--coverage-min` 提高项目门槛。不要为了通过检查扩展排除范围或降低标准。

源仓库另含 `templates` 真实继承资产检查。存在 API Web 冒烟入口时另执行 JS 编译和 Node 运行。Chrome 仅在活动 workspace 成员包含浏览器测试时要求，参照快照里的测试不触发前置要求。门禁包括 AI 资产/引用检查、架构边界、代码生成、只读格式检查、fatal-infos 分析、成员测试和覆盖率。生成物 `*.g.dart / *.freezed.dart` 不入库，不计手写覆盖率。含可执行逻辑的手写文件不能因为没有被测试导入就从统计消失；入口/平台代码若以构建验证，必须有明确范围和对应证据。

带 `dart:js_interop` 或 `package:web` 的浏览器实现不在 VM 中执行；覆盖率工具将其可执行行以 **零命中** 加入总分母，不能当作已覆盖或从统计消失。`check browser` 在真实 Chrome 中运行各成员 `test/browser`，已进入 validate。Browser 测试证明 IndexedDB/Blob 行为，VM LCOV 证明可测业务/UI/Native 分支；二者分别报告。Safari 和其他目标 OS 的实际运行另行记录。

分项检查使用 `python3 blueprint.py check <phase>`；可选 phase 见 `check --help`。`generate-check` 与 `generate` 都重建未入库的 Dart part，验证可重复生成，不是只读差异检查。工具说明见 [工具清单](tools.md)。新增或调整依赖后先执行 `check bootstrap`，再生成和检查。

国际化源检查由 `check l10n` 提供，并在生成前执行：拒绝缺失/多余键、空译文、重复 JSON 键及无效占位符元数据。源检查不依赖旧报告，ICU 语法由 `gen-l10n` 验证；语言切换和布局要求见 [国际化契约](architecture/localization.md)。

目标平台构建使用 `python3 blueprint.py build --app <path> --platforms <platforms>`。不同平台需要匹配主机与 SDK；验证矩阵分别记录生成、依赖、分析、测试、构建与实际运行。不得把 Web 构建成功折算成六端成功。

## AI 快速闭环与定向证据

先在准备好的 workspace 中使用显式目标，不运行 pub get 或 codegen：

```sh
python3 blueprint.py test --member packages/koi_ui --path test/koi_ui_test.dart
python3 blueprint.py test --member <成员路径> --path test/<用例>_test.dart --name '<名称正则>' --timeout 120
```

`--path` 可以重复，但首版只接受活动成员 test 下实际存在的 `_test.dart` 文件，不推断受影响依赖。`--platform chrome` 运行真实 Chrome 测试。`--name` 缩小声明范围；定向通过不代表成员、消费方或完整门禁通过。共享包修改仍须运行完整 `validate`；本轮没有覆盖率去重、缓存或自动范围选择。

每次运行在 `build/test-runs/<runId>/` 保存独立的 `events.jsonl`、`stderr.log`、源码指纹和 `result.json`，后者包含命令数组/cwd、源码前后摘要、环境、执行范围、退出码、耗时和清理结果。产物不入库、不作为模板输入。退出 0 只表示本次显式范围 passed；其余结果退出非零。`result.json` 不是所有命令 stdout 都是 JSON 的承诺，SDK 准备查询仍输出诊断行。

Workbench 的 W1–W6 覆盖真实存储的 UI 保存重开、失败重试、保存期间新编辑、关闭取消、不同工作区隔离和单写者占用；Native 使用临时目录，Chrome 使用独立 IndexedDB。Web Widget 测试使用受支持的 compact 外观，避免测试服务器缺失 InkSparkle shader，不模拟系统平台。Native 跨进程探针分两次启动写入与读取；集成测试通过准备关闭和释放宿主验证存储，不声称触发了操作系统退出事件。真实退出 binding 另由 Widget 测试验证。

同一 workspace 的 `test`、`check test/browser/coverage` 和 `validate` 使用操作系统文件锁互斥；锁忙时立即报 `workspace_busy`，不同 workspace 可并行。直接运行 `flutter test` 不受该锁保护，不要与这些命令在同一 workspace 混跑。停止进程后内核释放锁，锁文件本身保留并不代表运行中。Golden 诊断在锁内收集到本次运行目录，不清理旧诊断。

passed 需要完整且兼容的 runner 事件、正常退出、必需文件各有实际执行用例且无跳过，源码在执行期间不变。零实际用例记 not_run；缺失目标、截断/不兼容日志、摘要代替事件记 inconclusive；断言失败记 failed，编译/启动失败记 error，超时记 timeout。重放使用记录的 argv/cwd；要获得新证据，重新运行同一 blueprint test 命令。首版一次运行只有一次 attempt，无自动重试；不得覆盖旧失败或把重试成功改写为首次通过。

运行时探索先读取实际 tools/list 与 Widget 树，操作后断言业务状态，最后转为无 Agent 可运行的测试。官方 Dart MCP 可以配合独立 driver 入口；driver 扩展只能在该入口启用，生产 main 不导入它。测试宿主须保留自己的 binding/退出契约，不能复制 UI Lab 入口到已有自定义 binding 的宿主。探索与 runner 证据分开保存；MCP 的 isError:false 不替代测试门禁。

本轮真实样例是 UI Lab 的重命名：确认后读回去空白名称，切换页面后保持，空名称留在对话框，取消不提交。具体操作与已知 SDK 截图差异见样例 README；VM 与 Chrome 共享同一行为回归，Chrome 包装位于活动成员的 test/browser，因此由现有 browser 门禁执行。

## Golden 试点

`koi_ui/test/golden` 使用 Flutter 原生 matcher，首轮包含明/暗错误态和 320 宽、200% 字号中文空态。只使用随测试分发的固定中文字体子集，DPR 为 1；不依赖主机中文字体。基线环境限定 macOS arm64 + 项目固定 Flutter，其他主机明确 skip/NOT_RUN，不能报告跨平台像素一致。显式指定该文件给定向 CLI 时，全部跳过不会得到 passed。已有完整门禁及各平台测试保持原流程，首次远端 CI 结果仍须单独检查。

更新仅通过显式 `flutter test --update-goldens test/golden/status_golden_test.dart`，随后查看差异并普通重跑；定向 CLI 不暴露自动更新基线开关。不降低阈值、不因失败自动更新图片。首次中文字体基线与诊断能力验证后，再决定是否引入 Alchemist；首轮不新增 Golden 框架依赖。

## 测试环境

ProviderScope/ProviderContainer overrides 注入替身；auto-dispose provider 在观察期间保留 listen，结束时 dispose。文件测试用临时目录，服务/引擎/时钟经构造器注入。单测不使用用户素材库或生产后端。

长期草稿除 family 实例隔离外，还要验证应用根下的会话 scope 销毁后重建，确保新仓库和草稿生效。页面接线用两个真实编辑 Widget 验证输入、保存和失败互不影响；返回流程用实际路由 push/pop，不能用关闭 provider listener 代替。作为模板行为的回归放进 Feature 的测试目录，让生成项目一并继承。

原生关闭测试挂载真实 App，通过宿主 binding 的 handleRequestAppExit 发起退出，覆盖保存阻塞/失败/成功、重复请求以及晚注册的异步与取消监听器。全部监听器允许退出后，验证 Widget 消费者先卸载、拥有者后释放，继续 pump 不出现关闭订阅或已释放生命周期监听器的错误；直接调用某个 observer 或 bootstrap 不足以证明完整分发和渲染树顺序。

## 结果口径

仓库中的样例和测试定义验证范围，不是永久的通过声明。每次提交记录本次命令和结果；工具链缺失、未执行的平台、外部服务与真实设备验收独立列出。质量门禁通过也不代表产品发布或外部部署完成。
