# 独立业务模块示例

此 App 显式组合两个独立 package：`modules/alpha` 和 `modules/beta`。宿主只导入各模块公开入口；模块之间没有实现依赖，也不依赖宿主源码。

`packages/showcase_contracts` 提供纯 Dart repository/service 接口，以及位于 `presentation/providers` 的 Riverpod 注入契约。宿主在 `lib/bootstrap.dart` override 活跃 repository，按会话替换能力。宿主的事件总线跨模块存在，模块拥有自己的订阅和可取消延时任务。

每个模块公开 go_router 类型化入口。启动路径 `/beta/details` 会直接创建 Beta 会话，不需要先访问首页。切换只更新会话和路由重定向；宿主持有同一 GoRouter。界面的“延迟读取后立即切换”启动旧会话工作，再切换模块，展示取消与过期结果拒绝。

读取状态保留 loading/error；不会把失败当作空数据。`lib/core/providers/module_providers.dart` 演示 ChangeNotifier 生命周期对象到 Riverpod 的桥接，UI 只消费 provider 和调用意图方法。

此示例的契约不是所有 module 的必需依赖。生成器采用 `../minimal_module` 作为独立最小模板。

```sh
# 根目录完成 pub get 和 generate 后，从本目录执行
../../tool/flutterw test --no-pub --coverage
# 如本 checkout 尚未生成平台 runner：
../../tool/flutterw create --no-pub --empty --project-name module_showcase --platforms=android,ios,web,macos,windows,linux .
../../tool/flutterw run
```

宿主测试验证公开 capability 替换、直接打开详情、稳定路由、连续切换、旧结果拒绝和共享资源存活；各模块自己的测试验证取消、关闭、类型化路由和错误呈现。
