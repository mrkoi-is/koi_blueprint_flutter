# koi_diagnostics

Talker 5.2.0 的 Koi 适配，以及使用同一 DiagnosticStore 的只读 LAN 查看器。由 diagnostics v2 配方安装，公共入口为 koi_diagnostics.dart。TalkerDiagnosticRecorder 借用宿主 store；DiagnosticLan 拥有 HTTP/SSE 连接及 Android 前台保活，宿主必须 await close。

在该 package 目录运行固定 SDK 的 `flutter test --no-pub test/diagnostics_test.dart` 验证采集、凭证、导出、实时连接与端口释放。Android release 锁屏测试需要真机，桌面 loopback 不能替代。
