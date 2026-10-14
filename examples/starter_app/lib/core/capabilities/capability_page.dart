import 'package:starter_app/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

import 'package:starter_app/core/capabilities/app_capabilities.dart';

class CapabilityPage extends StatelessWidget {
  const CapabilityPage({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final page = appCapabilities.where((item) => item.id == id).firstOrNull;
    if (page != null) return page.builder(context);
    return Scaffold(
      appBar: AppBar(title: Text(id)),
      body: KoiErrorState(
        title: id,
        description: AppLocalizations.of(context)!.capabilityUnavailable,
      ),
    );
  }
}
