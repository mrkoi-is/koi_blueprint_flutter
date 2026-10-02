# koi_auth

通用认证状态契约，纯 Dart；不包含登录服务、token 存储或网络客户端。公开入口 [koi_auth.dart](lib/koi_auth.dart) 导出 AuthSession<TUser>，四个状态是 unauthenticated/loading/authenticated/failure，并提供 isAuthenticated。

宿主与 Feature 的 provider 负责操作和生命周期，koi_api_bootstrap 可选提供 token 会话。authenticated 持有用户与 token，默认 toString 不展开 token；实际日志调用方仍不得主动输出凭证。默认 minimal/workbench 不携带此包。

根目录 bootstrap/generate-check 后，本目录 `../../tool/flutterw test --no-pub`。测试检查各状态、用户字段和 token 不出现在默认字符串中。真实身份恢复和刷新 token 不是此包能力。
