import 'package:database_lab/l10n/generated/app_localizations.dart';
import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:database_lab/features/library/presentation/providers/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({required this.availability, super.key});
  final DatabaseAvailability availability;
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String _query = '';
  bool _archived = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final notes = ref.watch(
      libraryNotesProvider(query: _query, archived: _archived),
    );
    final command = ref.watch(libraryCommandsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.databaseTitle),
        actions: [
          IconButton(
            tooltip: strings.databaseNew,
            onPressed: command.isLoading ? null : () => _edit(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.availability.persistent
                            ? strings.databasePersistent
                            : strings.databaseTemporary,
                      ),
                      if (!widget.availability.multiTabSafe)
                        Text(strings.databaseSingleTab),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: strings.databaseSearch,
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            ),
                          ),
                          FilterChip(
                            label: Text(strings.databaseArchived),
                            selected: _archived,
                            onSelected: (value) =>
                                setState(() => _archived = value),
                          ),
                        ],
                      ),
                      if (command.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            strings.databaseOperationFailed('${command.error}'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (command.isLoading) const LinearProgressIndicator(),
                Expanded(
                  child: notes.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(strings.databaseReadFailed('$error')),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(libraryNotesProvider),
                            child: Text(strings.databaseRetry),
                          ),
                        ],
                      ),
                    ),
                    data: (rows) => rows.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? (_archived
                                        ? strings.databaseNoArchived
                                        : strings.databaseEmpty)
                                  : strings.databaseNoMatch,
                            ),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final note = rows[index];
                              return ListTile(
                                key: ValueKey(note.id),
                                title: Text(note.title),
                                subtitle: Text(
                                  [
                                    note.body,
                                    if (note.tags.isNotEmpty)
                                      note.tags
                                          .map((name) => '#$name')
                                          .join(' '),
                                  ].join('\n'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                isThreeLine: true,
                                onTap: command.isLoading
                                    ? null
                                    : () => _edit(note),
                                trailing: IconButton(
                                  tooltip: note.archived
                                      ? strings.databaseRestore
                                      : strings.databaseArchive,
                                  icon: Icon(
                                    note.archived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                  ),
                                  onPressed: command.isLoading
                                      ? null
                                      : () => ref
                                            .read(
                                              libraryCommandsProvider.notifier,
                                            )
                                            .archive(note.id, !note.archived),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit([LibraryNote? note]) => showDialog<void>(
    context: context,
    builder: (_) => _NoteEditor(note: note),
  );
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({this.note});
  final LibraryNote? note;
  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title);
  late final _body = TextEditingController(text: widget.note?.body);
  late final _tags = TextEditingController(text: widget.note?.tags.join(', '));
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final command = ref.watch(libraryCommandsProvider);
    return AlertDialog(
      title: Text(
        widget.note == null ? strings.databaseNew : strings.databaseEdit,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: strings.databaseDocumentTitle,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.databaseTitleRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _body,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: strings.databaseContents,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tags,
                  decoration: InputDecoration(
                    labelText: strings.databaseTags,
                    helperText: strings.databaseTagHint,
                  ),
                ),
                if (command.hasError)
                  Text(strings.databaseSaveFailed('${command.error}')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: command.isLoading ? null : () => Navigator.pop(context),
          child: Text(strings.databaseCancel),
        ),
        FilledButton(
          onPressed: command.isLoading ? null : _save,
          child: Text(
            command.isLoading ? strings.databaseSaving : strings.databaseSave,
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final success = await ref
        .read(libraryCommandsProvider.notifier)
        .save(
          id: widget.note?.id,
          title: _title.text,
          body: _body.text,
          tags: _tags.text.split(RegExp('[,，]')),
        );
    if (success && mounted) Navigator.pop(context);
  }
}
