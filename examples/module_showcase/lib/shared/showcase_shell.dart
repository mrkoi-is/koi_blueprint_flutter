import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:module_showcase/core/providers/module_providers.dart';

class ShowcaseShell extends ConsumerWidget {
  const ShowcaseShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(moduleSnapshotProvider);
    final runtime = ref.watch(moduleRuntimeProvider);
    final status = ref.watch(moduleControlsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('可选业务模块示例')),
      body: Column(
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final module in runtime.catalog.modules)
                OutlinedButton(
                  onPressed: () => unawaited(
                    ref.read(moduleControlsProvider.notifier).select(module.id),
                  ),
                  child: Text('切换 ${module.navigation.first.label}'),
                ),
              OutlinedButton(
                onPressed: () => unawaited(
                  ref
                      .read(moduleControlsProvider.notifier)
                      .setBetaConfigured(
                        !ref.read(showcaseServicesProvider).betaConfigured,
                      ),
                ),
                child: Text(
                  ref.read(showcaseServicesProvider).betaConfigured
                      ? '停用 Beta 配置'
                      : '启用 Beta 配置',
                ),
              ),
              OutlinedButton(
                onPressed: snapshot.session == null
                    ? null
                    : () => unawaited(
                        ref
                            .read(moduleControlsProvider.notifier)
                            .demonstrateStaleResult(),
                      ),
                child: const Text('延迟读取后立即切换'),
              ),
            ],
          ),
          Padding(padding: const EdgeInsets.all(12), child: Text(status)),
          if (snapshot.availability case final availability?
              when !availability.isAvailable)
            Text(availability.reason ?? '模块不可用'),
          if (snapshot.error != null) Text('装载失败：${snapshot.error}'),
          Expanded(
            child: snapshot.session == null
                ? Center(
                    child: Text(
                      snapshot.error == null ? '等待模块会话就绪' : '请选择模块重试',
                    ),
                  )
                : child,
          ),
        ],
      ),
    );
  }
}
