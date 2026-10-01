import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_admin_app/features/home/presentation/widgets/home_shell_scaffold.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return HomeShellScaffold(
      currentIndex: 1,
      title: '工作区设置',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user?.displayName ?? '未登录'),
              subtitle: Text('公司编码：${user?.companyCode ?? '-'}'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('环境与基建', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text('当前环境：${AppEnvironment.current.name}'),
                  Text('API Base URL：${AppEnvironment.current.apiBaseUrl}'),
                  const SizedBox(height: 12),
                  const Text('建议新增业务项目时继续保留：'),
                  const SizedBox(height: 8),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('packages/<project>_api')),
                      Chip(label: Text('packages/<project>_network')),
                      Chip(label: Text('apps/<app>/features/*')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () =>
                  unawaited(ref.read(authControllerProvider.notifier).logout()),
              icon: const Icon(Icons.logout),
              label: const Text('退出示例登录'),
            ),
          ),
        ],
      ),
    );
  }
}
