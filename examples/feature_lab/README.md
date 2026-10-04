# Feature Lab：三类受测生成源

这是 Feature 模板库，不是独立可启动 App（没有 main.dart）。公开入口 [feature_lab.dart](lib/feature_lab.dart) 导出 welcome/catalog/draft。blueprint feature 从这里按 kind 复制源码、改名、加入依赖和对应测试。

| kind | 参照 | 行为 |
| --- | --- | --- |
| presentation | welcome | 不依赖业务 provider 的展示页面 |
| api | catalog | domain repository、data source、注入 provider、刷新/分页及 loading/error/empty |
| local | draft | 条件文件存储、草稿状态、文本输入与外部恢复同步 |

根目录命令示例：`python3 blueprint.py feature apps/your_app drafts --kind local --dry-run`。目标必须是活动成员；正式生成后接入宿主导航和依赖注入。local 的 Native 文件实现不代表 Web 持久化；需要真实 Web 存储时参考 workbench 的 IndexedDB 适配。

根目录 bootstrap/generate-check 后，本目录运行 `../../tool/flutterw test --no-pub`。用临时文件和可控制请求测试保存失败、初次加载/刷新逆序、分页保留内容、页面挂载后的外部文本同步与销毁。

业务入口 feature_lab.dart 仅导出模型、端口和页面。宿主注入与测试另读 feature_lab_composition.dart（或各 Feature 的 composition 入口），无需从业务入口接触 IO 实现。生成到独立 module 后，宿主仍通过模块根入口消费，模块选择公开哪些业务/装配声明。

本地草稿使用 draftId 对应仓库、editorId 区分打开的编辑实例。宿主把这些 provider 放在明确的会话 scope，路由进入时创建稳定 editorId；返回路由保留未保存内容，关闭会话销毁 scope。真实路径/提交 API 通过仓库与提交 provider override 注入。

仓库/提交端口的 `dependencies: []`、Controller 的依赖链与页面的 `@Dependencies` 声明作用域依赖。宿主使用装配入口的 `draftSessionOverrides(repositories: {'default': repository})` 创建会话 ProviderScope 的 overrides；有提交能力时传入 `submissions`。该入口显式覆盖端口和 Controller family，父作用域已经读取同一编辑实例时也保持隔离。永久 [生命周期测试](test/features/draft/draft_lifecycle_test.dart)覆盖会话销毁重建、迟到保存、两个编辑页面的输入/保存/失败隔离，以及实际 Navigator push/pop。生成 local Feature 时同样继承这些测试。
