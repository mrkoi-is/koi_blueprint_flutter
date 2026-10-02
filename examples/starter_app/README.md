# Starter：minimal 生成源

最小 Flutter 宿主，消费 koi_ui 的明暗主题、ProviderScope 和类型化 go_router。App 持有稳定 router 并在 dispose 释放；不附带登录或网络业务。源码入口 [main.dart](lib/main.dart)，主题/路由装配见 [app.dart](lib/app.dart)。

使用源仓根目录 `python3 blueprint.py create demo --output ../demo --org com.example --platforms web` 生成独立项目，再进入 demo 执行 `python3 blueprint.py run --app apps/demo_app --device chrome`。平台 runner 由所选固定 SDK 创建，不将此源码目录当作六端验收结果。

根目录 bootstrap/generate-check 后，本目录执行 `../../tool/flutterw test --no-pub`。测试证明页面可达与主题渲染；生成项目的完整质量门禁使用它自己的 blueprint validate。源码在生成项目里保留为惰性参照，不成为活动依赖。
