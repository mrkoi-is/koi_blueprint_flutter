import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/application/media_engine_owner.dart';

import 'package:platform_lab/features/system_media/presentation/providers/system_media_providers.dart';

Widget buildSystemMediaPage(BuildContext context) => const SystemMediaPage();

class SystemMediaPage extends ConsumerStatefulWidget {
  const SystemMediaPage({super.key});
  @override
  ConsumerState<SystemMediaPage> createState() => _SystemMediaPageState();
}

class _SystemMediaPageState extends ConsumerState<SystemMediaPage>
    with WidgetsBindingObserver {
  bool _selectingEngine = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      SystemMediaRuntime.controller?.visibilityChanged(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: AppLocalizations.of(context)!.platformAudio,
          extensions: ['mp3', 'm4a', 'wav', 'ogg', 'flac'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    try {
      await SystemMediaRuntime.controller!.open(file.path, file.name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(systemMediaControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.platformSystemMedia),
      ),
      body: controller == null
          ? KoiErrorState(
              title: AppLocalizations.of(context)!.platformMediaUnavailable,
              description:
                  SystemMediaRuntime.error ??
                  AppLocalizations.of(context)!.platformMediaUninitialized,
              onRetry: () async {
                await initializeSystemMedia();
                ref.invalidate(systemMediaControllerProvider);
                if (mounted) setState(() {});
              },
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(AppLocalizations.of(context)!.platformEngineTitle),
                Text(AppLocalizations.of(context)!.platformEnginePolicy),
                for (final id
                    in SystemMediaRuntime.engines?.engineIds ?? <String>[]) ...[
                  ListTile(
                    title: Text(
                      id == 'media-kit' ? 'MediaKit' : 'Audioplayers',
                    ),
                    selected: SystemMediaRuntime.engines?.selectedId == id,
                    trailing: SystemMediaRuntime.engines?.selectedId == id
                        ? const Icon(Icons.check)
                        : null,
                    subtitle: Text(
                      SystemMediaRuntime.engines?.availability[id]?.reason ??
                          (SystemMediaRuntime
                                      .engines
                                      ?.availability[id]
                                      ?.isAvailable ==
                                  true
                              ? AppLocalizations.of(context)!
                                    .platformEngineReady
                              : AppLocalizations.of(context)!
                                    .platformEngineNotProbed),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _selectingEngine
                        ? null
                        : () async {
                            setState(() => _selectingEngine = true);
                            try {
                              await SystemMediaRuntime.engines?.select(id);
                            } finally {
                              if (mounted) {
                                setState(() => _selectingEngine = false);
                              }
                            }
                          },
                    child: Text(
                      AppLocalizations.of(context)!.platformEngineSelect,
                    ),
                  ),
                ],
                if (SystemMediaRuntime.engines?.error case final error?)
                  SelectableText(error),
                if (SystemMediaRuntime.transportError != null) ...[
                  OutlinedButton(
                    onPressed: () async {
                      await retrySystemTransport();
                      if (mounted) setState(() {});
                    },
                    child: Text(AppLocalizations.of(context)!.settingsRetry),
                  ),
                  SelectableText(
                    '${AppLocalizations.of(context)!.platformControlsUnavailable}: ${SystemMediaRuntime.transportError}',
                  ),
                ],
                FilledButton(
                  onPressed: SystemMediaRuntime.engines?.isReady == false
                      ? null
                      : _open,
                  child: Text(AppLocalizations.of(context)!.platformOpenAudio),
                ),
                SwitchListTile(
                  title: Text(
                    AppLocalizations.of(context)!.platformBackgroundAudio,
                  ),
                  value: controller.backgroundPlayback,
                  onChanged: (value) =>
                      setState(() => controller.backgroundPlayback = value),
                ),
                if (SystemMediaRuntime.engines?.isReady != false)
                  MediaTransport(controller: controller),
              ],
            ),
    );
  }
}

class MediaTransport extends StatelessWidget {
  const MediaTransport({required this.controller, super.key});
  final MediaSessionController controller;
  Future<void> _command(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The controller publishes a visible error through playbackState.
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: controller.playbackState,
    builder: (context, snapshot) {
      final engine = controller.engine;
      final ready = engine is! MediaEngineOwner || engine.isReady;
      final duration = engine.duration.inMilliseconds.toDouble();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            controller.selectedTitle ??
                AppLocalizations.of(context)!.platformNoAudio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (controller.error != null) Text(controller.error!),
          Slider(
            label: AppLocalizations.of(context)!.platformPlaybackPosition,
            min: 0,
            max: duration > 0 ? duration : 1,
            value: engine.position.inMilliseconds.toDouble().clamp(
              0,
              duration > 0 ? duration : 1,
            ),
            onChanged: duration > 0
                ? (value) => unawaited(
                    _command(
                      () => controller.seek(
                        Duration(milliseconds: value.round()),
                      ),
                    ),
                  )
                : null,
          ),
          IconButton(
            tooltip: engine.playing
                ? AppLocalizations.of(context)!.platformPause
                : AppLocalizations.of(context)!.platformPlay,
            icon: Icon(engine.playing ? Icons.pause : Icons.play_arrow),
            onPressed: controller.selectedTitle == null
                ? null
                : () => unawaited(
                    _command(
                      engine.playing ? controller.pause : controller.play,
                    ),
                  ),
          ),
          Slider(
            label: AppLocalizations.of(context)!.platformVolume,
            value: engine.volume.clamp(0, 1),
            onChanged: ready
                ? (value) =>
                      unawaited(_command(() => controller.setVolume(value)))
                : null,
          ),
        ],
      );
    },
  );
}
