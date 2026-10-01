import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcase_beta/src/features/welcome/presentation/providers/beta_providers.dart';

class BetaPage extends ConsumerWidget {
  const BetaPage({super.key, this.details = false, this.onOpenDetails});

  final bool details;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(betaMessageProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(details ? 'Beta detail page' : 'Beta home page'),
          const SizedBox(height: 12),
          message.when(
            data: (value) => Text(value),
            loading: () => const CircularProgressIndicator(),
            error: (_, _) => const Text('读取失败，请重试'),
          ),
          const SizedBox(height: 12),
          if (!details)
            FilledButton(
              onPressed: onOpenDetails,
              child: const Text('Beta details'),
            ),
        ],
      ),
    );
  }
}
