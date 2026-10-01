# 项目结构与迁移

## 放置决策

| 需求 | 位置 |
| --- | --- |
| 当前 App 的启动、路由、环境和原生装配 | apps/<app>/lib/core |
| 单一业务功能 | apps/<app>/lib/features/<feature> |
| 仅当前 App 复用的组件/工具 | apps/<app>/lib/shared |
| 具有独立依赖、生命周期、测试的业务模块 | modules/<module> |
| 稳定跨 App 共享能力 | packages/<package> |

Feature 根据职责拥有 `domain / data / application / presentation` 中所需的目录。`data` 负责 IO，`application` 负责业务状态和编排，可以同时存在。纯展示页不创建空的数据/领域层。Feature provider 统一放 `presentation/providers/`，展示 ViewModel 放 `presentation/models/`。

用 `python3 blueprint.py feature <app_or_module_path> <name> --kind presentation|api|local` 创建骨架；先用 `--dry-run` 查看落位。命令的 `|` 表示三选一，不是 shell 管道。详见 [创建项目](../new-project.md)。

## 平台目录

App 提交目标平台源码，生成物与构建产物保持忽略。新增平台使用固定 Flutter SDK 生成并核对组织标识、插件支持、权限配置和入口；只要求验证产品选定的平台。不要把已有 Web 样例当作移动或桌面构建证据。

## 迁移现有项目

1. 先列出当前入口、用户数据格式、基础设施、目标平台和回归测试。
2. 记录保留的行为和有理由的局部例外；不为目录一致性重写成熟引擎。
3. 在新边界注入既有服务，按 Feature 迁移并补回归。
4. 需要对照时可放 `legacy/`，不参与当前编译；删除旧代码前核对调用与迁移证据。

不复制其他业务项目的账号、平台标识、路径、业务术语或历史依赖覆盖。迁移和新建是不同任务，技能应识别二者。
