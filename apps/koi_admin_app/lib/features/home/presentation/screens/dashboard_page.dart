import 'package:flutter/material.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';
import 'package:koi_admin_app/features/home/presentation/widgets/home_shell_scaffold.dart';
import 'package:koi_domain/koi_domain.dart';

const _tiles = [
  KoiWorkspaceTile(
    title: '共享包优先',
    description: '先沉淀 packages，再落到具体 app，避免业务横向复制。',
    category: 'packages',
    highlighted: true,
  ),
  KoiWorkspaceTile(
    title: 'API 生成独立',
    description: '生成物、网络编排、业务消费分层隔离，便于后续接 koi_swagger_parser。',
    category: 'api',
  ),
  KoiWorkspaceTile(
    title: 'AI 资产内置',
    description: 'AGENTS、skills、cursor rules 一起进仓库，开箱即用。',
    category: 'ai',
  ),
  KoiWorkspaceTile(
    title: 'legacy 可归档',
    description: '旧 GetX 或混合架构项目可以先归档到 legacy，再逐步重写。',
    category: 'migration',
  ),
];

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeShellScaffold(
      currentIndex: 0,
      title: '控制台总览',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Koi Flutter 新架构基线',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前环境：${AppEnvironment.current.name} · ${AppEnvironment.current.apiBaseUrl}',
                    ),
                    const SizedBox(height: 16),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('workspace + melos')),
                        Chip(label: Text('Riverpod 3')),
                        Chip(label: Text('go_router')),
                        Chip(label: Text('Freezed')),
                        Chip(label: Text('koi_network')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Blueprint 原则', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 1100 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tiles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2.3,
                  ),
                  itemBuilder: (context, index) {
                    final tile = _tiles[index];
                    return Card(
                      color: tile.highlighted
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.08)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Chip(label: Text(tile.category.toUpperCase())),
                            const SizedBox(height: 12),
                            Text(
                              tile.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(tile.description),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
