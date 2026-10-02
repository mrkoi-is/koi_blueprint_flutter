import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:platform_lab/features/desktop_window/application/window_host.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';
import 'package:platform_lab/features/system_media/presentation/providers/system_media_providers.dart';
import 'package:platform_lab/features/system_media/presentation/system_media_page.dart';

Widget buildMiniPlayerPage(BuildContext context) => const MiniPlayerPage();

class MiniPlayerPage extends ConsumerStatefulWidget {
  const MiniPlayerPage({super.key});
  @override
  ConsumerState<MiniPlayerPage> createState() => _MiniPlayerPageState();
}

class _MiniPlayerPageState extends ConsumerState<MiniPlayerPage> {
  DesktopWindowHost? _window;
  @override
  void dispose() {
    // Navigation away restores geometry and topmost state, even without Back.
    final host = _window;
    if (host?.mini == true) unawaited(host!.setMini(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(desktopWindowHostProvider);
    _window = host;
    final media = ref.watch(systemMediaControllerProvider);
    if (host == null || !host.ready || media == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.platformMiniPlayer),
        ),
        body: KoiEmptyState(
          title: AppLocalizations.of(context)!.platformMiniRequirement,
          description: AppLocalizations.of(context)!.platformMiniHint,
        ),
      );
    }
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            host.mini
                ? AppLocalizations.of(context)!.platformMiniPlayer
                : AppLocalizations.of(context)!.platformMediaLayout,
          ),
          actions: [
            IconButton(
              tooltip: host.mini
                  ? AppLocalizations.of(context)!.platformRestoreWindow
                  : AppLocalizations.of(context)!.platformEnterMini,
              icon: Icon(
                host.mini ? Icons.open_in_full : Icons.picture_in_picture_alt,
              ),
              onPressed: () => unawaited(host.setMini(!host.mini)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (host.error != null) Text(host.error!),
              MediaTransport(controller: media),
            ],
          ),
        ),
      ),
    );
  }
}
