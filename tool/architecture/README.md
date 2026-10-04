# 可执行架构边界

从仓库根目录运行 `python3 blueprint.py check architecture`。底层入口为
`dart run tool/check_architecture.dart --root <workspace> [--json]`。
成员事实源是 `dart pub workspace list --json`，运行依赖来自成员的
`pubspec.yaml`；不维护第二份成员清单。

| 规则 | 可检查的结构事实 |
| --- | --- |
| ARCH001 | shared package 不依赖 App/module；module 不依赖 App/其他 module；App 不依赖其他 App。检查 runtime dependencies 以及 import/export，包括条件分支和相对路径。 |
| ARCH002 | 外部访问独立 module 时仅允许 `package:<name>/<name>.dart`；module 内部允许内部引用。 |
| ARCH003 | domain 和基础纯 Dart 包不得依赖 Flutter、Riverpod、网络/存储实现或 feature 实现层。koi_ui 允许 Flutter/Material/dart:ui 展示能力，禁止平台 IO、浏览器/媒体适配、业务状态与实现层。检查所有手写 lib 的 import/export、条件分支及递归运行依赖。 |
| ARCH004 | feature 中 `@riverpod` / `@Riverpod` 的 provider 生成声明放在 `presentation/providers`；`core` 的基础设施装配不受此目录限制；消费者的 `@Dependencies` 元数据不生成 provider。 |
| ARCH005 | Riverpod provider 使用注解生成；拒绝手写 Provider/NotifierProvider 等构造与 factory 调用。 |
| ARCH006 | presentation 页面/组件不导入 IO、网络客户端或 feature data 实现；通过 providers 和 domain 访问。 |
| ARCH007 | Widget build 与 provider build 不直接调用可识别 dart:io 接收者的同步方法；async 关键字不使阻塞 IO 变为异步。命令回调由 ARCH011 计数。 |
| ARCH008 | feature data/application 不反向导入 presentation。 |
| ARCH009 | apps/packages/modules/examples 中真实存在的 package 必须在 Pub 的成员列表里，不能把模板移出验证范围。 |
| ARCH010 | warning：State/ConsumerState 实例字段超过 8 个，同一声明分别计数，static 不计入。审查职责、生命周期和状态归属。 |
| ARCH011 | warning：Widget 回调超过 4 个；函数字段、构造参数、函数 typedef 与 Flutter 回调类型计数。审查展示接口，不要求机械 provider 化。 |
| ARCH012 | 已退役，编号保留。媒体探测解析由具体产品行为测试验证。 |
| ARCH013 | `shell/coordinators/` 不导入路径中含 `/presentation/` 的 URI、解析结果或 workspace 内重导出闭包。壳层页面组合（如 `app_shell.dart`）仍可引用 feature 页面。 |

生成的 `.g.dart`/`.freezed.dart` 由生成与 analyze 检查，结构检查扫描成员的手写
`lib`。语法错误以 ARCH000 失败。测试包含每条规则的正例、反例及合法例外；运行
`dart run tool/tests/architecture_test.dart`。

## 输出与退出合同

JSON 保留 `ok`、`issues` 及 issue 原字段，每项增加 `severity`，汇总为 `summary.errors` 与 `summary.warnings`。`ok` 只取决于 error；warning-only 可以通过。Dart 入口退出码为 0（无 error）、1（架构错误）、2（配置/执行失败）。Python 主入口继续将底层非零结果映射为既有失败退出码 2。

## 有理由的局部例外

`tool/architecture_exceptions.json` 默认为空。每条例外必须精确匹配检查输出的
rule/path/line/target，并说明保留原因；不接受目录通配。ARCH010 与 ARCH011 还必须给出
整数 `budget`，兼容已有数量例外；超预算或失效时返回 warning。其他硬规则不接受 budget，失效或不唯一仍返回 error。ARCH012 旧例外可读但提示删除；非法 schema、路径、重复项或预算仍属于配置失败。

```json
{
  "version": 1,
  "exceptions": [
    {
      "rule": "ARCH006",
      "path": "apps/example/lib/features/legacy/presentation/legacy.dart",
      "line": 8,
      "target": "package:dio/dio.dart",
      "reason": "迁移期保留已有适配器，替换完成后连同此例外删除。"
    }
  ]
}
```

## 检查范围

规则使用 Dart analyzer 的语法树解析声明、调用与导入，不执行代码，也不是完整
类型解析或调用图分析。它不能证明隐藏在业务方法里的 IO、资源所有权、状态语义、
异步取消或平台运行正确。动态访问、第三方包内部、重导出的符号和任意辅助函数
仍需行为测试与审查。同步 IO 检查覆盖显式的 dart:io 类型、构造和局部变量，
不会把所有名字带 Sync 的业务方法都判成 IO。

AI 入口与 Skill 资产另由 `python3 blueprint.py check ai` 验证：索引、正文元数据、
本地文档引用、生成源与配套测试目录以及未展开的命名占位符。
样例编译和行为验证由正常 workspace 的 generate/analyze/test 负责。
