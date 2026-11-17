import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_diagnostics/koi_diagnostics.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/installed_diagnostics.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/application/diagnostic_export.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/presentation/providers/diagnostic_providers.dart';
import 'package:__APP_PACKAGE__/l10n/generated/app_localizations.dart';

Widget buildDiagnosticsPage(BuildContext context) => const DiagnosticsPage();

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({
    super.key,
    this.exporter = exportDiagnostics,
    this.lan,
  });
  final DiagnosticsExporter exporter;
  final DiagnosticLan? lan;
  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

// These filters, page cursor and export feedback are transient view state;
// the host runtime owns capture, persistence and the remote server.
class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final _search = TextEditingController();
  final _source = TextEditingController();
  AppLogLevel? _level;
  String _kind = 'log';
  int? _cursor;
  int _revision = -1;
  List<DiagnosticEvent> _items = [];
  bool _exporting = false;
  String? _message;
  DiagnosticQuery get _query => DiagnosticQuery(
    level: _level,
    text: _search.text,
    source: _source.text.trim().isEmpty ? null : _source.text.trim(),
    kind: _kind,
  );
  DiagnosticStrings get strings {
    final locale = Localizations.localeOf(context);
    return DiagnosticStrings(
      locale.scriptCode == 'Hant' ? 'zh_Hant' : locale.languageCode,
    );
  }

  void _read({bool append = false}) {
    final store = ref.read(diagnosticStoreProvider);
    final page = store.query(_query, cursor: append ? _cursor : null);
    final entries = append ? [..._items, ...page.items] : page.items;
    final seen = <Object>{};
    _items = entries.where((e) => seen.add(e.network?['id'] ?? e.id)).toList();
    _cursor = page.nextCursor;
    _revision = page.revision;
  }

  void _refresh() => setState(() => _read());
  Future<void> _export(bool filtered) async {
    setState(() {
      _exporting = true;
      _message = null;
    });
    try {
      final result = await widget.exporter(
        ref
            .read(diagnosticStoreProvider)
            .exportSnapshot(filtered ? _query : const DiagnosticQuery()),
      );
      if (mounted) setState(() => _message = result);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.watch(diagnosticRevisionProvider);
    final store = ref.watch(diagnosticStoreProvider);
    if (_revision != store.revision) _read();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'log', label: Text(strings.logs)),
                    ButtonSegment(
                      value: 'network',
                      label: Text(strings.network),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (value) => setState(() {
                    _kind = value.single;
                    _read();
                  }),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(labelText: l10n.diagSearch),
                    onChanged: (_) => _refresh(),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _source,
                    decoration: InputDecoration(labelText: l10n.diagSource),
                    onChanged: (_) => _refresh(),
                  ),
                ),
                DropdownButton<AppLogLevel?>(
                  value: _level,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.diagAllLevels),
                    ),
                    for (final level in AppLogLevel.values)
                      DropdownMenuItem(value: level, child: Text(level.name)),
                  ],
                  onChanged: (value) => setState(() {
                    _level = value;
                    _read();
                  }),
                ),
                FilledButton.tonal(
                  onPressed: _exporting ? null : () => _export(true),
                  child: Text(l10n.diagExportFiltered),
                ),
                TextButton(
                  onPressed: _exporting ? null : () => _export(false),
                  child: Text(l10n.diagExportAll),
                ),
                TextButton(onPressed: _refresh, child: Text(l10n.diagRefresh)),
              ],
            ),
          ),
          if (widget.lan ?? diagnosticLan case final lan?)
            _LanControls(lan: lan, strings: strings),
          if (store.persistenceError != null) Text(l10n.diagStorageFailed),
          if (_message != null) SelectableText(_message!),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text(strings.empty))
                : ListView.builder(
                    itemCount: _items.length + (_cursor == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return TextButton(
                          onPressed: () => setState(() => _read(append: true)),
                          child: Text(strings.loadMore),
                        );
                      }
                      final e = _items[index];
                      return ListTile(
                        title: Text(e.message),
                        subtitle: Text(
                          '${e.time.toLocal()} · ${e.source} · ${e.network?['state'] ?? e.level.name}',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(e.source),
                            content: SizedBox(
                              width: 700,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  const JsonEncoder.withIndent('  ')
                                      .convert(e.toJson()),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  MaterialLocalizations.of(context)
                                      .closeButtonLabel,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LanControls extends StatefulWidget {
  const _LanControls({required this.lan, required this.strings});
  final DiagnosticLan lan;
  final DiagnosticStrings strings;
  @override
  State<_LanControls> createState() => _LanControlsState();
}

class _LanControlsState extends State<_LanControls> {
  String? _interface;
  Future<void> _start() async {
    final addresses = await widget.lan.interfaces();
    if (!mounted) return;
    if (addresses.isEmpty) {
      await widget.lan.start(language: widget.strings.language);
      return;
    }
    _interface = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(widget.strings.lan),
        children: [
          for (final address in addresses)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, address),
              child: Text(address),
            ),
        ],
      ),
    );
    if (!mounted || _interface == null) return;
    await widget.lan.start(
      address: _interface,
      language: widget.strings.language,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lan,
    builder: (context, _) {
      final lan = widget.lan;
      if (!lan.supported) return Text(widget.strings.unsupported);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(widget.strings.lan),
                TextButton(
                  onPressed: lan.busy
                      ? null
                      : lan.running
                      ? lan.stop
                      : _start,
                  child: Text(
                    lan.running ? widget.strings.stop : widget.strings.start,
                  ),
                ),
                if (lan.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (lan.address != null)
                  TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: lan.address!)),
                    child: Text(lan.address!),
                  ),
              ],
            ),
            if (lan.credential != null)
              SelectableText('${widget.strings.credential}: ${lan.credential}'),
            if (lan.notificationGranted == false)
              Text(widget.strings.notificationDenied),
            if (lan.batteryOptimizationIgnored == false)
              Text(widget.strings.batteryLimited),
            if (lan.error != null)
              Text('${widget.strings.failed}: ${lan.error}'),
          ],
        ),
      );
    },
  );
}
