# Feature 执行契约

| 模式 | 最小职责 | 必查行为 |
| --- | --- | --- |
| presentation | 页面/展示组件 | 可达性、props、交互 |
| api | domain 契约、data 替身或适配、provider、页面 | loading/error/data、重试、override |
| local | domain 契约、按需 data 与 application、provider、页面 | 状态变更、资源释放、迟到结果 |

生成文件后检查宿主路由和 bootstrap。Feature 私有 provider 统一放 presentation/providers；不要同时创建两套 controller。需要实际 IO 时用 repository 隔离，不把状态机搬进 Widget。

样例数据和内存仓库要在代码/交付中说明用途。真实 API URL、文件根目录和平台服务由宿主注入，不在生成模板绑定本机环境。

测试通过公共行为观察结果，不只断言生成文件存在。修改模板时在临时 workspace 生成并运行对应测试，至少覆盖三种模式和名称/目录冲突。

源码布局由生成器统一解析：App 的默认根为 lib/features，package/module 为 lib/src/features；既有单一根优先，双根拒绝，测试统一 test/features。模块入口识别无需新类型登记，宿主不能从 module/src 导入内部 Feature。

api/local 的业务入口 `<name>.dart` 与宿主装配入口 `<name>_composition.dart` 分开。页面、模型和端口从业务入口消费；实现和 override 声明由宿主装配使用。模块只通过根入口选择公开这些声明。

状态按作用域判断：页面独占筛选/显示模式留 Widget，查询与提交由 Controller，长期草稿由显式 route/session scope 与实例 key 隔离。数量 warning 不决定状态必须放在哪里。
