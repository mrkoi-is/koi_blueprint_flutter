# 项目结构与迁移策略

## App 内部目录

```text
apps/<app>/lib/
├── app.dart
├── main.dart
├── core/
│   ├── config/
│   ├── providers/
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
