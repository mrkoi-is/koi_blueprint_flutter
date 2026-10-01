import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcase_alpha/src/features/welcome/presentation/providers/alpha_providers.dart';

class AlphaPage extends ConsumerWidget {
  const AlphaPage({super.key, this.details = false, this.onOpenDetails});

  final bool details;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(alphaMessageProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(details ? 'Alpha detail page' : 'Alpha home page'),
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
              child: const Text('Alpha details'),
            ),
        ],
      ),
    );
  }
}
