import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';
import 'package:module_showcase/features/module_capabilities/domain/text_analysis.dart';
import 'package:module_showcase/features/module_capabilities/presentation/providers/analysis_providers.dart';
import 'package:module_showcase/l10n/generated/app_localizations.dart';

Widget buildModuleCapabilitiesPage(BuildContext context) =>
    const ModuleCapabilitiesPage();

class ModuleCapabilitiesPage extends StatefulWidget {
  const ModuleCapabilitiesPage({super.key});
  @override
  State<ModuleCapabilitiesPage> createState() => _ModuleCapabilitiesPageState();
}

class _ModuleCapabilitiesPageState extends State<ModuleCapabilitiesPage> {
  final _session = AnalysisSession();
  late final void Function() _unregister;
  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async => true,
      close: _session.close,
    );
    unawaited(_session.activate('words'));
  }

  @override
  void dispose() {
    _unregister();
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [analysisSessionProvider.overrideWithValue(_session)],
    child: const _AnalysisPage(),
  );
}

class _AnalysisPage extends ConsumerStatefulWidget {
  const _AnalysisPage();
  @override
  ConsumerState<_AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<_AnalysisPage> {
  final _text = TextEditingController(text: 'One shared contract');
  TextAnalysis? _result;
  Object? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
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
            onChanged: (enabled) => _run(() async {
              setState(() => owner.charactersEnabled = enabled);
              if (state.session?.moduleId == 'characters') {
                await owner.activate('characters', restart: true);
              }
            }),
          ),
          CheckboxListTile(
            title: Text(strings.moduleCapabilitiesFailNext),
            value: owner.failNextCreation,
            onChanged: (value) =>
                setState(() => owner.failNextCreation = value ?? false),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ['words', 'characters'])
                FilledButton(
                  onPressed: state.isSwitching
                      ? null
                      : () => _run(() => owner.activate(id, restart: true)),
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
          if (_error != null || state.error != null)
            Text('${_error ?? state.error}'),
          TextField(
            controller: _text,
            decoration: InputDecoration(
              labelText: strings.moduleCapabilitiesInput,
            ),
            minLines: 2,
            maxLines: 5,
          ),
          FilledButton(
            onPressed: state.session == null
                ? null
                : () => _run(() async {
                    final result = await owner.analyze(_text.text);
                    if (mounted) setState(() => _result = result);
                  }),
            child: Text(strings.moduleCapabilitiesRun),
          ),
          if (_result != null)
            Text(
              strings.moduleCapabilitiesResult(
                _result!.engine == 'words'
                    ? strings.moduleCapabilitiesWords
                    : strings.moduleCapabilitiesCharacters,
                _result!.count,
              ),
            ),
          Text(strings.moduleCapabilitiesClosed(owner.closedEngines)),
        ],
      ),
    );
  }
}
