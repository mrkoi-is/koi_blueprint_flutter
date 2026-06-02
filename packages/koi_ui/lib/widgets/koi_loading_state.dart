import 'package:flutter/material.dart';

class KoiLoadingState extends StatelessWidget {
  const KoiLoadingState({super.key, this.message = '正在准备工作区...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator.adaptive(),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
