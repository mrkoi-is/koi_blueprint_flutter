# Koi Admin 认证样例

源仓库的认证宿主，演示 bootstrap、AuthSession、token 存储/401 隔离、Riverpod 注入与类型化路由。公开入口是 [main.dart](lib/main.dart)，装配见 [bootstrap.dart](lib/bootstrap.dart)。当前仅有 Web runner；这是样例范围，默认 minimal/workbench 不继承认证依赖。

从 workspace 根目录执行 `python3 blueprint.py run --app apps/koi_admin_app --device chrome`，debug 默认 dev Mock。`staging/prod` 未接真实认证/API 时明确拒绝启动；release 禁止 dev Mock，build 命令为此样例传 ENV=prod。构建产物存在不代表真实登录已可用。Native token 存储能力由支持包测试，当前 App 没有原生 runner 验收。

验证：根目录 `python3 blueprint.py check generate-check` 后，在本目录执行 `../../tool/flutterw test --no-pub`。测试覆盖环境拒绝、启动失败、登录/退出、过期请求和 router 生命周期。完整门禁与平台证据分别用 blueprint validate/build。
