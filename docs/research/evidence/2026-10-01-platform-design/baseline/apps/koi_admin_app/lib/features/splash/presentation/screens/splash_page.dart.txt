import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_admin_app/core/router/app_navigation.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_ui/koi_ui.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navigated || !mounted) {
        return;
      }
      final authenticated = ref.read(isAuthenticatedProvider);
      _navigated = true;
      if (!mounted) {
        return;
      }
      if (authenticated) {
        context.goToDashboard();
      } else {
        context.goToLogin();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: KoiLoadingState(message: '正在装配 Koi Flutter 工作区...'),
    );
  }
}
