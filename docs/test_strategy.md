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

门禁包括 AI 资产/引用检查、架构边界、代码生成、只读格式检查、fatal-infos 分析、成员测试和覆盖率。生成物 `*.g.dart / *.freezed.dart` 不入库，不计手写覆盖率。含可执行逻辑的手写文件不能因为没有被测试导入就从统计消失；入口/平台代码若以构建验证，必须有明确范围和对应证据。

带 `dart:js_interop` 或 `package:web` 的浏览器实现不在 VM 中执行；覆盖率工具将其可执行行以 **零命中** 加入总分母，不能当作已覆盖或从统计消失。`check browser` 在真实 Chrome 中运行各成员 `test/browser`，已进入 validate。Browser 测试证明 IndexedDB/Blob 行为，VM LCOV 证明可测业务/UI/Native 分支；二者分别报告。Safari 和其他目标 OS 的实际运行另行记录。

分项检查使用 `python3 blueprint.py check <phase>`；可选 phase 见 `check --help`。新增或调整依赖后先执行 `check bootstrap`，再生成和检查。

目标平台构建使用 `python3 blueprint.py build --app <path> --platforms <platforms>`。不同平台需要匹配主机与 SDK；验证矩阵分别记录生成、依赖、分析、测试、构建与实际运行。不得把 Web 构建成功折算成六端成功。

## 测试环境

ProviderScope/ProviderContainer overrides 注入替身；auto-dispose provider 在观察期间保留 listen，结束时 dispose。文件测试用临时目录，服务/引擎/时钟经构造器注入。单测不使用用户素材库或生产后端。

## 结果口径

仓库中的样例和测试定义验证范围，不是永久的通过声明。每次提交记录本次命令和结果；工具链缺失、未执行的平台、外部服务与真实设备验收独立列出。质量门禁通过也不代表产品发布或外部部署完成。
