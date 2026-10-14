# 可运行样例与源码参照

这份目录是规范/Skill 到真实源码的唯一样例地图。蓝图仓库直接使用下列路径；生成项目将参照源码快照放到 `.blueprint/reference/` 并调整本页链接。快照只供阅读，不作为生成项目的活动 workspace 成员。

| 样例 | 学习重点 | 源码 |
| --- | --- | --- |
| Starter | 最小宿主、基础注入和运行测试，不附带登录/API | [starter_app](../examples/starter_app/) |
| UI Lab | 标准组件六类目录、主题/密度、表单校验、选择/排序、菜单/反馈与自适应工作区 | [ui_lab](../examples/ui_lab/) |
| Workbench | 文本、图片/视频、任务、Native/Web 持久化；可选生成模板 | [workbench_app](../examples/workbench_app/) |
| Feature Lab | presentation/api/local 三类 Feature、provider 和测试 | [feature_lab](../examples/feature_lab/) |
| 认证样例 | 完整 auth、loading/error、并发防护、bootstrap 和路由 | [auth](../apps/koi_admin_app/lib/features/auth/)、[bootstrap](../apps/koi_admin_app/lib/bootstrap.dart)、[router](../apps/koi_admin_app/lib/core/router/)、[测试](../apps/koi_admin_app/test/) |
| 最小业务模块 | module 命令的受测源模板，不依赖 Showcase 业务服务 | [minimal_module](../examples/minimal_module/) |
| 模块契约 | 不可变 catalog、session 拥有者、切换与过期结果 | [koi_modules](../packages/koi_modules/) |
| 模块宿主 | 两个业务模块、共享契约、路由和注入 | [module_showcase](../examples/module_showcase/) |

样例是相应行为的参照，不代表用户项目已完成真实后端、持久化或所有平台验收。修改模板或关键 Skill 后，应在临时 workspace 实际生成并测试，不能只检查这份路径表。

## 已有行为修复的起点

先在以下入口复现并定位。无需为一次回调修复阅读整个 Feature；只有错误来自 IO、注入或释放时，才沿下一节的数据流扩展。

| 任务 | 首先读取 | 继续追踪的条件 |
| --- | --- | --- |
| 列表失败重试 | [页面事件](../examples/feature_lab/lib/features/catalog/presentation/screens/catalog_page.dart)、[CatalogController](../examples/feature_lab/lib/features/catalog/presentation/providers/catalog_providers.dart)、[查询行为测试](../examples/feature_lab/test/features/catalog/catalog_test.dart) | 请求或返回模型不符合契约时，追踪 CatalogRepository；替身不能注入时，再看装配入口 |
| 双编辑实例隔离 | [DraftPage 实例参数](../examples/feature_lab/lib/features/draft/presentation/screens/draft_page.dart)、[DraftController family](../examples/feature_lab/lib/features/draft/presentation/providers/draft_providers.dart)、[编辑与提交测试](../examples/feature_lab/test/features/draft/draft_test.dart) | 持久化内容错误时追踪 DraftRepository；离开会话仍残留时检查宿主 scope |
| 模块切换拒绝迟到结果 | [ModuleSessionContext.guard](../packages/koi_modules/lib/src/module_session.dart)、[KoiModuleRuntime](../packages/koi_modules/lib/src/module_runtime.dart)、[生命周期测试](../packages/koi_modules/test/module_lifecycle_test.dart) | 切换入口或共享服务拥有者不明确时，再看模块宿主 bootstrap |

## 按任务读取

| 路线 | 页面与状态拥有者 | 数据端口与实现 | 装配与行为测试 |
| --- | --- | --- | --- |
| 纯展示 | [WelcomePage](../examples/feature_lab/lib/features/welcome/presentation/screens/welcome_page.dart)，不可变值与回调；简单 UI 状态留 Widget | 无 IO 端口，无空 domain/data 层 | [业务入口](../examples/feature_lab/lib/features/welcome/welcome.dart)；[交互测试](../examples/feature_lab/test/features/welcome/welcome_test.dart) |
| API 查询与提交 | [CatalogPage](../examples/feature_lab/lib/features/catalog/presentation/screens/catalog_page.dart) → [CatalogController](../examples/feature_lab/lib/features/catalog/presentation/providers/catalog_providers.dart)（查询/分页/重试）；[DraftPage](../examples/feature_lab/lib/features/draft/presentation/screens/draft_page.dart) → [DraftController](../examples/feature_lab/lib/features/draft/presentation/providers/draft_providers.dart)（保存/提交与编辑实例） | [CatalogRepository](../examples/feature_lab/lib/features/catalog/domain/catalog_repository.dart) → [仓库实现](../examples/feature_lab/lib/features/catalog/data/catalog_repository_impl.dart) → [DataSource](../examples/feature_lab/lib/features/catalog/data/catalog_data_source.dart)；[DraftRepository/Submission](../examples/feature_lab/lib/features/draft/domain/draft_repository.dart) | [Catalog 装配入口](../examples/feature_lab/lib/features/catalog/catalog_composition.dart)、[Draft 装配入口](../examples/feature_lab/lib/features/draft/draft_composition.dart)由宿主 override；[查询行为](../examples/feature_lab/test/features/catalog/catalog_test.dart)、[提交/双实例行为](../examples/feature_lab/test/features/draft/draft_test.dart) |
| 长期本地任务 | [TasksPage](../examples/workbench_app/lib/features/workspace/presentation/screens/tasks_page.dart) → [同步投影](../examples/workbench_app/lib/features/workspace/presentation/providers/workspace_providers.dart) → [WorkspaceSession](../examples/workbench_app/lib/features/workspace/application/workspace_session.dart) → [Persistence](../examples/workbench_app/lib/features/workspace/application/workspace_persistence.dart) / [ImportWorkflow](../examples/workbench_app/lib/features/workspace/application/workspace_import_workflow.dart) / [ThumbnailWorkflow](../examples/workbench_app/lib/features/workspace/application/workspace_thumbnail_workflow.dart) | [存储/选择端口](../examples/workbench_app/lib/features/workspace/domain/workspace_ports.dart) → [Native/Web 存储装配](../examples/workbench_app/lib/features/workspace/data/workspace_storage.dart) | [bootstrap](../examples/workbench_app/lib/bootstrap.dart)创建并释放 Session/播放器/存储；[保存、取消与恢复](../examples/workbench_app/test/features/workspace/application/workspace_session_test.dart)、[关闭与重绑定](../examples/workbench_app/test/bootstrap_presentation_test.dart)、[真实平台运行](../examples/workbench_app/integration_test/README.md) |

追踪媒体时从 [MediaPage](../examples/workbench_app/lib/features/workspace/presentation/screens/media_page.dart) 读取 [MediaPreviewSession](../examples/workbench_app/lib/features/workspace/application/media_preview_session.dart)、[播放端口](../examples/workbench_app/lib/features/workspace/application/media_playback.dart)、[MediaKit 适配](../examples/workbench_app/lib/features/workspace/data/media/media_kit_playback.dart) 和 [展示句柄](../examples/workbench_app/lib/features/workspace/presentation/media/media_surface_handle.dart)。[媒体行为测试](../examples/workbench_app/test/media_preview_session_test.dart)固定同素材身份、迟到截图与释放顺序。
