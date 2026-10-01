# Feature 执行契约

| 模式 | 最小职责 | 必查行为 |
| --- | --- | --- |
| presentation | 页面/展示组件 | 可达性、props、交互 |
| api | domain 契约、data 替身或适配、provider、页面 | loading/error/data、重试、override |
| local | domain 契约、按需 data 与 application、provider、页面 | 状态变更、资源释放、迟到结果 |

生成文件后检查宿主路由和 bootstrap。Feature 私有 provider 统一放 presentation/providers；不要同时创建两套 controller。需要实际 IO 时用 repository 隔离，不把状态机搬进 Widget。

样例数据和内存仓库要在代码/交付中说明用途。真实 API URL、文件根目录和平台服务由宿主注入，不在生成模板绑定本机环境。

测试通过公共行为观察结果，不只断言生成文件存在。修改模板时在临时 workspace 生成并运行对应测试，至少覆盖三种模式和名称/目录冲突。
