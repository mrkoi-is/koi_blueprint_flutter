# Feature Lab：三类受测生成源

这是 Feature 模板库，不是独立可启动 App（没有 main.dart）。公开入口 [feature_lab.dart](lib/feature_lab.dart) 导出 welcome/catalog/draft。blueprint feature 从这里按 kind 复制源码、改名、加入依赖和对应测试。

| kind | 参照 | 行为 |
| --- | --- | --- |
| presentation | welcome | 不依赖业务 provider 的展示页面 |
| api | catalog | domain repository、data source、注入 provider、刷新/分页及 loading/error/empty |
| local | draft | 条件文件存储、草稿状态、文本输入与外部恢复同步 |

根目录命令示例：`python3 blueprint.py feature apps/your_app drafts --kind local --dry-run`。目标必须是活动成员；正式生成后接入宿主导航和依赖注入。local 的 Native 文件实现不代表 Web 持久化；需要真实 Web 存储时参考 workbench 的 IndexedDB 适配。

根目录 bootstrap/generate-check 后，本目录运行 `../../tool/flutterw test --no-pub`。用临时文件和可控制请求测试保存失败、初次加载/刷新逆序、分页保留内容、页面挂载后的外部文本同步与销毁。
