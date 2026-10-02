import 'package:device_lab/l10n/generated/app_localizations.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/local_setup/presentation/providers/local_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalSetupPage extends ConsumerStatefulWidget {
  const LocalSetupPage({super.key, required this.onboarding});
  final bool onboarding;
  @override
  ConsumerState<LocalSetupPage> createState() => _LocalSetupPageState();
}

class _LocalSetupPageState extends ConsumerState<LocalSetupPage> {
  final _body = TextEditingController();
  final _uri = TextEditingController(text: 'koi://tasks');
  bool _busy = false;
  Object? _error;
  @override
  void dispose() {
    _body.dispose();
    _uri.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localSetupChangesProvider);
    final session = ref.watch(localSetupSessionProvider);
    final setup = session.onboarding.state;
    final locale = setup.language;
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
    if (_body.text != session.draft) {
      _body.value = TextEditingValue(
        text: session.draft,
        selection: TextSelection.collapsed(offset: session.draft.length),
      );
    }
    final configuring =
        widget.onboarding && setup.step != OnboardingStep.complete;
    Future<void> next(OnboardingStep step) => session.configure(
      OnboardingState(
        step: step,
        language: setup.language,
        directory: setup.directory,
        device: setup.device,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.onboarding
              ? strings.localSetupFirstSetup
              : strings.localSetupIncomingIntents,
        ),
        actions: [
          if (widget.onboarding && !configuring)
            IconButton(
              tooltip: strings.localSetupReconfigure,
              onPressed: () => _run(() => next(OnboardingStep.language)),
              icon: const Icon(Icons.settings),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null || session.error != null)
            Text(
              '${_error ?? session.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (configuring) ...[
            Text(strings.localSetupSetup(setup.step.index + 1)),
            if (setup.step == OnboardingStep.language) ...[
              DropdownButton<String>(
                value: setup.language,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(strings.devicesSystemLanguage),
                  ),
                  const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                  const DropdownMenuItem(value: 'zh-Hant', child: Text('繁體中文')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => _run(
                        () => session.configure(
                          OnboardingState(
                            step: setup.step,
                            language: value!,
                            directory: setup.directory,
                            device: setup.device,
                          ),
                        ),
                      ),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => next(OnboardingStep.directory)),
                child: Text(strings.localSetupNext),
              ),
            ],
            if (setup.step == OnboardingStep.directory) ...[
              Text(
                setup.directory ??
                    strings.localSetupNoDirectoryWebUsesTheBrowser,
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(session.chooseDirectory),
                child: Text(strings.localSetupChooseDirectory),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => next(OnboardingStep.device)),
                child: Text(strings.localSetupNext),
              ),
            ],
            if (setup.step == OnboardingStep.device) ...[
              Text(strings.localSetupDocumentsStayLocalInstallTheLan),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => next(OnboardingStep.complete)),
                child: Text(strings.localSetupFinish),
              ),
            ],
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => session.configure(
                        OnboardingState(
                          step: OnboardingStep.complete,
                          language: setup.language,
                          directory: setup.directory,
                          skipped: true,
                        ),
                      ),
                    ),
              child: Text(strings.localSetupSkipForNow),
            ),
          ] else ...[
            Text(
              '${strings.localSetupCurrentPage}: ${session.tab == 'tasks' ? strings.devicesTasksTab : strings.devicesDocumentsTab} · ${session.documents.length} ${strings.localSetupDocuments}',
            ),
            if (session.incoming.pendingCount > 0)
              Text(
                strings.localSetupDraftProtectedPendingIntents(
                  session.incoming.pendingCount,
                ),
              ),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 10,
              onChanged: session.edit,
              decoration: InputDecoration(labelText: strings.localSetupText),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _run(session.save),
                  child: Text(strings.localSetupSave),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(session.discard),
                  child: Text(strings.localSetupDiscardDraft),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(session.importPicked),
                  child: Text(strings.localSetupImportTextFile),
                ),
              ],
            ),
            if (!widget.onboarding) ...[
              TextField(
                controller: _uri,
                decoration: InputDecoration(
                  labelText: strings.localSetupIncomingUri,
                ),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => session.receive(Uri.parse(_uri.text))),
                child: Text(strings.localSetupOpenIntent),
              ),
              Text(strings.localSetupSupportsKoiTasksKoiDocumentId),
            ],
          ],
        ],
      ),
    );
  }
}
