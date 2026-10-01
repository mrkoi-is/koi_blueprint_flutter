import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Scaffold(
      body: KoiErrorState(
        title: '应用初始化失败',
        description: '请检查环境配置与网络初始化设置后重新启动。${kDebugMode ? '\n$error' : ''}',
      ),
    ),
  );
}
