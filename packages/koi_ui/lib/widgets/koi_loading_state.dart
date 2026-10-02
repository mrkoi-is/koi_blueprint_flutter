import 'package:koi_ui/l10n/koi_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/widgets/koi_status_layout.dart';

class KoiLoadingState extends StatelessWidget {
  const KoiLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return KoiStatusLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            message ?? KoiUiStrings.of(context).loading,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
