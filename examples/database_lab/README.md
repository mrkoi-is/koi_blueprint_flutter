# Database Lab

可运行的资料库配方：创建/编辑正文与多个标签、搜索、归档/恢复；界面订阅真实关系查询。App 宿主持有 `LibrarySession`，注解式 Riverpod 借用 Repository；domain 不导入 Drift 或平台 API。默认 minimal 模板无需依赖数据库。

- Native 使用 `NativeDatabase.createInBackground`，实际 SQLite 文件位于 application support；移动和桌面使用同一 Repository。
- Web 使用 `WasmDatabase.open` 与固定 Drift 2.35.1 官方 worker/WASM；优先 OPFS，缺少隔离头时可使用 SharedWorker + IndexedDB。启动结果明确暴露持久化/多标签页能力；临时存储模式在界面显示。
- 资料、标签和关系更新在一个事务内完成；多标签查询不使用逗号拼接，标签中的引号和逗号完整保留。
- schema v2 的归档字段有真实操作；v1→v2 用事务升级并验证外键。`test/fixtures/library_v1.sqlite` 非空旧库包含中文、两条资料和三条关联标签，与旁边 SQL 对应。失败升级保留 v1 可再次打开，不能把 SQLite schema version 当业务修订号使用。
- 正常可取消退出等待数据库关闭；Web 强制关页不承诺异步等待。逐次写入事务负责已提交数据的持久化。

从 workspace 根目录安装依赖并统一生成后，在此目录：

```sh
../../.fvm/flutter_sdk/bin/flutter test --no-pub
../../.fvm/flutter_sdk/bin/flutter run --no-pub -d chrome
../../.fvm/flutter_sdk/bin/flutter build web --no-pub
```

Native runner 由固定 Flutter SDK 在生成项目中创建；本示例的 Native 文件持久化与后台线程通过 VM 测试验证，各 Native App 真机/模拟器验收需分别记录。

## 可复现的浏览器持久化验收

要求固定 Dart SDK、Node 22+、已安装 Chrome。Linux 可用 `CHROME_EXECUTABLE=/path/to/chrome`。脚本只启动临时本地 server/独立 Chrome profile，结束会关闭、删除自己创建的 profile，不使用个人浏览器数据。

```sh
python3 tool/prepare_web_smoke.py
../../.fvm/flutter_sdk/bin/dart compile js -O2 tool/database_web_smoke.dart -o build/web-smoke/database_smoke.js
node tool/run_web_smoke.mjs
node tool/run_web_smoke.mjs --isolated
```

第一条 Chrome 运行验证无 COOP/COEP 时的 `sharedIndexedDb`，第二条提供隔离头验证 `opfsLocks`。每次用唯一数据库执行非空 v1 迁移失败/重试、关系查询、关闭重开、双连接订阅、跨表回滚，最后关闭和删除自己的数据库。输出包含实际选择的 mode；不将内存模式算作持久化通过。双连接验证跨连接订阅，不替代两个独立浏览器 tab 的界面验收。

`web/drift-assets.json` 固定下载 URL、版本、大小与 SHA256；prepare 脚本先核验。普通运行不需要联网下载 SQLite。升级 Drift 时同时替换同一官方 release 的 WASM/worker 并更新哈希、重跑两个模式。需要自行编译 worker 可用 `dart compile js -O4 web/drift_worker.dart`；编译物不能直接沿用旧哈希。

本轮已执行：Native/Widget 7 tests、Chrome sharedIndexedDb/OPFS 两模式、Web release build。六端 App 实际运行、浏览器私密模式和跨 tab 操作仍需各自目标环境证据。来源：[Native 后台执行](https://drift.simonbinder.eu/platforms/vm/)、[Web 平台与 worker](https://drift.simonbinder.eu/platforms/web/)、[迁移事务](https://drift.simonbinder.eu/migrations/api/)。

安装配方同时复制 `test/features/library` 的 Native SQLite 行为测试、非空 v1 fixture 和 `test/browser/library_browser_test.dart`。浏览器测试从 Flutter 测试服务器的 `test/fixtures/database_web/` 读取与 `web/` 相同的固定版本 WASM/worker，实际打开持久化后端并验证迁移、重开与 watch；它不使用内存替身。

```sh
../../.fvm/flutter_sdk/bin/flutter test --no-pub --platform chrome test/browser/library_browser_test.dart
```

性能样本与口径见仓库 `docs/validation/2026-10-02-spotube-upgrade/performance/architecture-data.md`；`tool/perf/database_benchmark_test.dart` 使用真实后台 SQLite 连接与临时数据库，不属于默认测试目录。
