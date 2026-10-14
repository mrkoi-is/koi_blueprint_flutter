# koi_core

所有新项目默认携带的纯 Dart 基础包；不依赖宿主、Flutter Widget 或业务 repository。公开入口 [koi_core.dart](lib/koi_core.dart) 导出 AppFailure、Result/FutureResult、success/failure、StringX 与可注入 AppLogger。

业务层通过 Result 表达成功/错误；UI 文案与错误展示留在 presentation。AppLogger 的 sink 由宿主配置，底层不自行读取 UI/provider。领域特有模型放对应 Feature 或稳定契约包，避免把 core 变成业务集合。

在 workspace 根目录完成 bootstrap 和 generate-check 后，在本目录运行 `../../tool/flutterw test --no-pub`。测试覆盖错误分支、字符串空白、Result 和日志 sink。生成的 Freezed part 不入库。
