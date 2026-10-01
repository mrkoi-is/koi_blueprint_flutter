import 'package:flutter/material.dart';
import 'package:koi_ui/widgets/koi_status_layout.dart';

class KoiLoadingState extends StatelessWidget {
  const KoiLoadingState({super.key, this.message = '正在准备工作区...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return KoiStatusLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
