import 'package:riverpod_annotation/experimental/scope.dart';

import 'dart:async';

import 'package:koi_core/koi_core.dart' show CapabilityStatus;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:module_showcase/features/module_capabilities/presentation/providers/analysis_providers.dart';
import 'package:module_showcase/l10n/generated/app_localizations.dart';

Widget buildModuleCapabilitiesPage(BuildContext context) =>
    const ModuleCapabilitiesPage();

class ModuleCapabilitiesPage extends StatelessWidget {
  const ModuleCapabilitiesPage({super.key});
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [analysisSessionProvider.overrideWith(analysisSession)],
    child: const _AnalysisPage(),
  );
}

@Dependencies([AnalysisCommands, analysisSession, analysisState])
class _AnalysisPage extends ConsumerStatefulWidget {
  const _AnalysisPage();
  @override
  ConsumerState<_AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<_AnalysisPage> {
  final _text = TextEditingController(text: 'One shared contract');
  AnalysisCommands get _commands => ref.read(analysisCommandsProvider.notifier);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final draft = ref.watch(analysisCommandsProvider);
    final result = draft.result;
    final error = draft.error;
    final owner = ref.watch(analysisSessionProvider);
    final state = ref.watch(analysisStateProvider).value ?? owner.runtime.state;
    return Scaffold(
      appBar: AppBar(title: Text(strings.moduleCapabilitiesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            strings.moduleCapabilitiesOperations(
              owner.runtime.catalog.modules
                  .expand((module) => module.capabilities)
                  .join(', '),
            ),
          ),
          SwitchListTile(
            title: Text(strings.moduleCapabilitiesEnableCharacters),
            value: owner.charactersEnabled,
            onChanged: (enabled) => unawaited(_commands.setCharacters(enabled)),
          ),
          CheckboxListTile(
            title: Text(strings.moduleCapabilitiesFailNext),
            value: owner.failNextCreation,
            onChanged: (value) => _commands.setFailNext(value ?? false),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ['words', 'characters'])
                FilledButton(
                  onPressed: state.isSwitching
                      ? null
                      : () => unawaited(_commands.select(id)),
                  child: Text(
                    id == 'words'
                        ? strings.moduleCapabilitiesWords
                        : strings.moduleCapabilitiesCharacters,
                  ),
                ),
            ],
          ),
          if (state.isSwitching) const LinearProgressIndicator(),
          if (state.availability != null)
            Text(switch (state.availability!.status) {
              CapabilityStatus.available => strings.moduleCapabilitiesAvailable,
              CapabilityStatus.unavailable =>
                strings.moduleCapabilitiesUnavailable,
              CapabilityStatus.unsupported =>
                strings.moduleCapabilitiesUnsupported,
            }),
          if (error != null || state.error != null)
            Text('${error ?? state.error}'),
          TextField(
            controller: _text,
            onChanged: _commands.setInput,
            decoration: InputDecoration(
              labelText: strings.moduleCapabilitiesInput,
            ),
            minLines: 2,
            maxLines: 5,
          ),
          FilledButton(
            onPressed: state.session == null
                ? null
                : () => unawaited(_commands.analyze()),
            child: Text(strings.moduleCapabilitiesRun),
          ),
          if (result != null)
            Text(
              strings.moduleCapabilitiesResult(
                result.engine == 'words'
                    ? strings.moduleCapabilitiesWords
                    : strings.moduleCapabilitiesCharacters,
                result.count,
              ),
            ),
          Text(strings.moduleCapabilitiesClosed(owner.closedEngines)),
        ],
      ),
    );
  }
}
