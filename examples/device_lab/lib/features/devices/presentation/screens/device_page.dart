import 'package:device_lab/l10n/generated/app_localizations.dart';

import 'dart:convert';

import 'package:device_lab/features/devices/application/device_lab_session.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:device_lab/features/devices/presentation/providers/device_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DevicePage extends ConsumerStatefulWidget {
  const DevicePage({super.key});
  @override
  ConsumerState<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends ConsumerState<DevicePage> {
  final _uri = TextEditingController(text: 'ws://127.0.0.1:8080/commands');
  final _code = TextEditingController();
  final _link = TextEditingController(text: 'koi://document?id=welcome');
  final _editor = TextEditingController();
  bool _working = false;
  @override
  void dispose() {
    _uri.dispose();
    _code.dispose();
    _link.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function(DeviceLabSession) action) async {
    if (_working) return;
    setState(() => _working = true);
    await ref
        .read(deviceSessionProvider)
        .act(() => action(ref.read(deviceSessionProvider)));
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(deviceStateProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, stack) => Scaffold(body: Center(child: Text('$error'))),
        data: _build,
      );
  Widget _build(DeviceLabSnapshot state) {
    final session = ref.read(deviceSessionProvider);
    final locale = state.onboarding.language;
    final strings = locale == 'system'
        ? AppLocalizations.of(context)!
        : lookupAppLocalizations(
            locale == 'zh-Hant'
                ? const Locale.fromSubtags(
                    languageCode: 'zh',
                    scriptCode: 'Hant',
                  )
                : Locale(locale),
          );
    if (_editor.text != state.draft) {
      _editor.value = TextEditingValue(
        text: state.draft,
        selection: TextSelection.collapsed(offset: state.draft.length),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.devicesDevicesAndIncomingEvents),
        actions: [
          IconButton(
            tooltip: strings.devicesSetupAgain,
            onPressed: _working
                ? null
                : () => _action((session) => session.configureAgain()),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_working) const LinearProgressIndicator(),
            if (state.error != null)
              Text(
                '${state.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (state.onboarding.step != OnboardingStep.complete)
              ..._onboarding(state, strings),
            if (state.onboarding.step == OnboardingStep.complete) ...[
              Text(strings.devicesDocumentsStayOnThisDevicePairing),
              const SizedBox(height: 12),
              Text(
                strings.devicesLocalDocuments,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              OutlinedButton(
                onPressed: _working || state.dirty
                    ? null
                    : () =>
                          _action((session) => session.importPickedDocument()),
                child: Text(strings.devicesImportText),
              ),
              if (state.activeTab == 'tasks')
                Text(strings.devicesIncomingEventOpenedTasksSummaryRefresh),
              DropdownButtonFormField<String>(
                key: ValueKey('document_${state.selectedId}'),
                initialValue: state.selectedId,
                decoration: InputDecoration(labelText: strings.devicesDocument),
                items: [
                  for (final entry in state.documents.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value['title']!),
                    ),
                ],
                onChanged: _working
                    ? null
                    : (value) {
                        if (value != null) {
                          _action((session) async {
                            await session.selectDocument(value);
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editor,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(labelText: strings.devicesContents),
                onChanged: session.edit,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _working || !state.dirty
                        ? null
                        : () => _action((session) => session.saveDraft()),
                    child: Text(strings.devicesSave),
                  ),
                  TextButton(
                    onPressed: _working || !state.dirty
                        ? null
                        : () => _action((session) => session.discardDraft()),
                    child: Text(strings.devicesDiscardDraftAndContinue),
                  ),
                  if (state.pendingIntents > 0)
                    TextButton(
                      onPressed: session.dismissIncoming,
                      child: Text(strings.devicesDismissIncomingEvents),
                    ),
                ],
              ),
              if (state.pendingIntents > 0)
                Text(
                  strings.devicesIncomingEventsAwaitDraftResolution(
                    state.pendingIntents,
                  ),
                ),
              const Divider(height: 32),
              Text(
                strings.devicesIncomingLinks,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  labelText:
                      'koi://document?id=welcome / koi://tasks / file://…',
                ),
              ),
              OutlinedButton(
                onPressed: _working
                    ? null
                    : () => _action((session) async {
                        await session.receiveUri(Uri.parse(_link.text.trim()));
                      }),
                child: Text(strings.devicesOpenLink),
              ),
              if (state.message != null) Text(strings.devicesIncomingReceived),
              const Divider(height: 32),
              Text(
                strings.devicesPairDevices,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (session.canHost)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _working || state.hostUri != null
                          ? null
                          : () => _action((session) => session.host()),
                      child: Text(strings.devicesHostOnLocalhost),
                    ),
                    OutlinedButton(
                      onPressed: _working || state.hostUri != null
                          ? null
                          : () => _action(
                              (session) => session.host(localNetwork: true),
                            ),
                      child: Text(strings.devicesAllowLanPairing),
                    ),
                    if (state.hostUri != null)
                      TextButton(
                        onPressed: _working
                            ? null
                            : () => _action((session) => session.stopHosting()),
                        child: Text(strings.devicesStopHosting),
                      ),
                  ],
                ),
              if (!session.canHost)
                Text(strings.devicesThisPlatformIsAForegroundClient),
              if (state.hostUri != null)
                SelectableText(
                  '${state.hostUri}\n${strings.devicesPairingCode}: ${state.pairingCode}',
                ),
              OutlinedButton(
                onPressed: _working
                    ? null
                    : () => _action((session) => session.discover()),
                child: Text(strings.devicesDiscoverLanDevices),
              ),
              for (final device in state.discovered)
                ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.uri.toString()),
                  onTap: () =>
                      setState(() => _uri.text = device.uri.toString()),
                ),
              TextField(
                controller: _uri,
                decoration: InputDecoration(
                  labelText: strings.devicesDeviceWebsocketAddress,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: strings.devicesPairingCode,
                ),
                keyboardType: TextInputType.number,
              ),
              FilledButton(
                onPressed: _working
                    ? null
                    : () => _action(
                        (session) => session.connect(
                          Uri.parse(_uri.text.trim()),
                          _code.text.trim(),
                        ),
                      ),
                child: Text(strings.devicesPairAndReadSummary),
              ),
              Text(
                '${strings.devicesConnection}: ${switch (state.connection) {
                  DeviceConnectionState.disconnected => strings.devicesConnectionDisconnected,
                  DeviceConnectionState.connecting => strings.devicesConnectionConnecting,
                  DeviceConnectionState.paired => strings.devicesConnectionPaired,
                  DeviceConnectionState.reconnecting => strings.devicesConnectionReconnecting,
                  DeviceConnectionState.failed => strings.devicesConnectionFailed,
                  DeviceConnectionState.closed => strings.devicesConnectionClosed,
                }}',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final command in DeviceCommand.values)
                    OutlinedButton(
                      onPressed:
                          _working ||
                              state.connection != DeviceConnectionState.paired
                          ? null
                          : () => _action((session) => session.send(command)),
                      child: Text(switch (command) {
                        DeviceCommand.summary => strings.devicesRefreshSummary,
                        DeviceCommand.pauseTask => strings.devicesPauseTask,
                        DeviceCommand.resumeTask => strings.devicesResumeTask,
                      }),
                    ),
                ],
              ),
              Text(
                '${strings.devicesLocalSummaryRefresh}: ${state.paused ? strings.devicesPaused : strings.devicesRunning} · ${state.completed}',
              ),
              if (state.remoteSummary != null)
                SelectableText(
                  const JsonEncoder.withIndent('  ')
                      .convert(state.remoteSummary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _onboarding(DeviceLabSnapshot state, AppLocalizations strings) {
    final setup = state.onboarding;
    Future<void> advance(
      OnboardingStep step, {
      String? language,
      String? directory,
    }) => _action(
      (session) => session.saveOnboarding(
        OnboardingState(
          step: step,
          language: language ?? setup.language,
          directory: directory ?? setup.directory,
          device: setup.device,
        ),
      ),
    );
    return [
      Text(
        strings.devicesFirstSetup(setup.step.index + 1),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      if (setup.step == OnboardingStep.language) ...[
        DropdownButtonFormField<String>(
          initialValue: setup.language,
          decoration: InputDecoration(labelText: strings.devicesLanguage),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(strings.devicesSystemLanguage),
            ),
            const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
            const DropdownMenuItem(value: 'zh-Hant', child: Text('繁體中文')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: _working
              ? null
              : (value) => advance(OnboardingStep.language, language: value),
        ),
        FilledButton(
          onPressed: _working ? null : () => advance(OnboardingStep.directory),
          child: Text(strings.devicesNext),
        ),
      ],
      if (setup.step == OnboardingStep.directory) ...[
        Text(
          setup.directory ?? strings.devicesOptionalChooseADefaultDirectoryThis,
        ),
        OutlinedButton(
          onPressed: _working
              ? null
              : () => _action((session) async {
                  await session.chooseDirectory();
                }),
          child: Text(strings.devicesChooseDirectory),
        ),
        FilledButton(
          onPressed: _working ? null : () => advance(OnboardingStep.device),
          child: Text(strings.devicesNext),
        ),
      ],
      if (setup.step == OnboardingStep.device) ...[
        Text(strings.devicesPairingIsOptionalAfterSetupSelect),
        FilledButton(
          onPressed: _working ? null : () => advance(OnboardingStep.complete),
          child: Text(strings.devicesFinishSetup),
        ),
      ],
      TextButton(
        onPressed: _working
            ? null
            : () => _action((session) => session.skipOnboarding()),
        child: Text(strings.devicesSkipAndSetUpLater),
      ),
    ];
  }
}
