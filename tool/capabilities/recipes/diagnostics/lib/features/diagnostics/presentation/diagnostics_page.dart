import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/application/diagnostic_export.dart';
import 'package:__APP_PACKAGE__/features/diagnostics/presentation/providers/diagnostic_providers.dart';
import 'package:__APP_PACKAGE__/l10n/generated/app_localizations.dart';

Widget buildDiagnosticsPage(BuildContext context) => const DiagnosticsPage();

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key, this.exporter = exportDiagnostics});
  final DiagnosticsExporter exporter;
  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final _search = TextEditingController();
  final _source = TextEditingController();
  AppLogLevel? _level;
  List<DiagnosticEvent> _items = [];
  int? _cursor;
  int _revision = 0;
  bool _exporting = false;
  String? _message;
  DiagnosticQuery get _query => DiagnosticQuery(
    level: _level,
    text: _search.text,
    source: _source.text.trim().isEmpty ? null : _source.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read({bool append = false}) {
    final page = ref
        .read(diagnosticStoreProvider)
        .query(_query, cursor: append ? _cursor : null);
    _items = append ? [..._items, ...page.items] : page.items;
    _cursor = page.nextCursor;
    _revision = page.revision;
  }

  void _refresh() => setState(_read);
  Future<void> _export(bool filtered) async {
    setState(() {
      _exporting = true;
      _message = null;
    });
    try {
      final snapshot = ref
          .read(diagnosticStoreProvider)
          .exportSnapshot(filtered ? _query : const DiagnosticQuery());
      final result = await widget.exporter(snapshot);
      if (mounted) {
        setState(() => _message = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
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
                  onChanged: (level) => setState(() {
                    _level = level;
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
                if (store.revision > _revision)
                  TextButton(
                    onPressed: _refresh,
                    child: Text(l10n.diagRefresh),
                  ),
              ],
            ),
          ),
          if (store.persistenceError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l10n.diagStorageFailed),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(_message!),
            ),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text(l10n.diagEmpty))
                : ListView.builder(
                    itemCount: _items.length + (_cursor == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return TextButton(
                          onPressed: () => setState(() => _read(append: true)),
                          child: Text(l10n.diagMore),
                        );
                      }
                      final event = _items[index];
                      return ListTile(
                        key: ValueKey(event.id),
                        title: Text(
                          event.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${event.time.toLocal()} · ${event.level.name} · ${event.source}',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(event.source),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                '${event.message}\n${event.error ?? ''}\n${event.stack ?? ''}',
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              BuildInfo.current
                  .toJson()
                  .entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join(' · '),
            ),
          ),
        ],
      ),
    );
  }
}
