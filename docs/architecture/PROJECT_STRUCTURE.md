# 项目结构与迁移策略

## App 内部目录

```text
apps/<app>/lib/
├── app.dart
├── main.dart
├── core/
│   ├── config/
│   ├── bootstrap/
│   └── router/
├── features/
│   └── <feature>/
│       ├── data/
│       │   ├── datasources/
│       │   └── repositories/
│       ├── domain/
│       │   ├── entities/
│       │   └── repositories/
│       └── presentation/
│           ├── providers/
│           ├── screens/
│           └── widgets/
└── shared/
```

三层是标准骨架；纯展示型 Feature（如 `splash`）允许只保留 `presentation/` 层。
脚手架可使用 `python3 scripts/create_feature.py apps/<app> <feature> --presentation-only`
生成轻量目录，不为展示页创建空的数据与领域层。

可运行 App 还必须提交至少一个目标平台目录。本蓝图提交 `apps/koi_admin_app/web/`，
并通过固定 Flutter SDK 执行 release build 验证。

## 新旧项目迁移建议

如果你是在旧项目上重写，而不是从蓝图直接起盘，推荐保留：

```text
legacy/
```

用途：
- 存放旧 GetX / 旧 MVC / 旧混合架构代码
- 只读参考，不参与编译
- 业务逻辑迁移完成后再逐步删除

这部分思路参考了 `learning_officer_oa` 的历史目录组织经验，但蓝图本身不再引入 GetX。
