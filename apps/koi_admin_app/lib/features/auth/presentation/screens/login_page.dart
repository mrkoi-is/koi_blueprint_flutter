import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_auth/koi_auth.dart';
import 'package:koi_domain/koi_domain.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final TextEditingController _companyCodeController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    final demoMode = AppEnvironment.current.usesMockAuth;
    _companyCodeController = TextEditingController(text: demoMode ? 'KOI' : '');
    _usernameController = TextEditingController(text: demoMode ? 'admin' : '');
    _passwordController = TextEditingController(text: demoMode ? '123456' : '');
  }

  @override
  void dispose() {
    _companyCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSession<KoiUser>>(authControllerProvider, (previous, next) {
      if (!mounted) {
        return;
      }
      next.whenOrNull(
        failure: (message) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      );
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5EFE6), Color(0xFFE8F1EC)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Koi Admin Blueprint',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppEnvironment.current.usesMockAuth
                            ? '当前为本地演示认证，不会持久化登录令牌。'
                            : '请输入生产认证服务提供的账号信息。',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text('ENV: ${AppEnvironment.current.name}'),
                          ),
                          const Chip(label: Text('Riverpod 3')),
                          const Chip(label: Text('go_router')),
                          const Chip(label: Text('Freezed')),
                          const Chip(label: Text('koi_network')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _companyCodeController,
                        decoration: const InputDecoration(
                          labelText: '公司编码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '账号',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: '密码',
                          helperText: AppEnvironment.current.usesMockAuth
                              ? '示例密码固定为 123456'
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => unawaited(
                                  ref
                                      .read(authControllerProvider.notifier)
                                      .login(
                                        companyCode:
                                            _companyCodeController.text,
                                        username: _usernameController.text,
                                        password: _passwordController.text,
                                      ),
                                ),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(isLoading ? '登录中...' : '进入控制台'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
