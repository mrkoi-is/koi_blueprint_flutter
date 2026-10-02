import 'package:workbench_app/l10n/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_retry.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});
  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _newTodo = TextEditingController();
  bool _onlyOpen = false;
  @override
  void dispose() {
    _newTodo.dispose();
    super.dispose();
  }

  Future<void> _rename(WorkspaceTodo todo) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TodoTitleDialog(title: todo.title),
    );
    if (mounted && title != null && title.trim().isNotEmpty) {
      ref
          .read(workspaceSessionProvider)
          .updateTodo(todo.id, title: title.trim());
    }
  }

  Future<void> _delete(WorkspaceTodo todo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTodo),
        scrollable: true,
        content: Text(context.l10n.deleteTodoConfirm(todo.title)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      ref.read(workspaceSessionProvider).deleteTodo(todo.id);
    }
  }

  void _add() {
    final title = _newTodo.text.trim();
    if (title.isEmpty) {
      return;
    }
    ref.read(workspaceSessionProvider).addTodo(title);
    _newTodo.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workspaceSessionProvider);
    final state = ref.watch(
      workspaceStateProvider.select(
        (value) => (
          todos: value.value?.snapshot.todos ?? session.state.snapshot.todos,
          jobCount:
              value.value?.snapshot.jobs.length ??
              session.state.snapshot.jobs.length,
        ),
      ),
    );
    final todos = state.todos
        .where((todo) => !_onlyOpen || !todo.completed)
        .toList();
    return ListView(
      key: const PageStorageKey('tasks-scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        KoiSection(
          title: Text(context.l10n.todos),
          description: Text(context.l10n.todosDescription),
          actions: [
            FilterChip(
              label: Text(context.l10n.incompleteOnly),
              selected: _onlyOpen,
              onSelected: (value) => setState(() => _onlyOpen = value),
            ),
          ],
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('new-todo'),
                      controller: _newTodo,
                      decoration: InputDecoration(
                        labelText: context.l10n.addTodo,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.addTodo,
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              for (final todo in todos)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 400;
                    final actions = Wrap(
                      children: [
                        IconButton(
                          tooltip: context.l10n.renameTodoNamed(todo.title),
                          onPressed: () => unawaited(_rename(todo)),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: context.l10n.deleteTodoNamed(todo.title),
                          onPressed: () => unawaited(_delete(todo)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Checkbox(
                            semanticLabel: todo.title,
                            value: todo.completed,
                            onChanged: (value) => session.updateTodo(
                              todo.id,
                              completed: value ?? false,
                            ),
                          ),
                          title: Text(todo.title),
                          trailing: narrow ? null : actions,
                        ),
                        if (narrow)
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                      ],
                    );
                  },
                ),
              if (todos.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(context.l10n.noTodos),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        KoiSection(
          title: Text(context.l10n.jobs),
          description: Text(context.l10n.jobsDescription),
          child: Column(
            children: [
              if (state.jobCount == 0)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(context.l10n.noJobs),
                ),
              for (final job in session.state.snapshot.jobs.reversed)
                _JobTile(key: ValueKey(job.id), id: job.id),
            ],
          ),
        ),
      ],
    );
  }
}

String _status(BuildContext context, JobStatus status) => switch (status) {
  JobStatus.queued => context.l10n.queued,
  JobStatus.running => context.l10n.running,
  JobStatus.cancelling => context.l10n.cancelling,
  JobStatus.succeeded => context.l10n.succeeded,
  JobStatus.failed => context.l10n.failed,
  JobStatus.cancelled => context.l10n.cancelled,
  JobStatus.interrupted => context.l10n.interrupted,
};

class _JobTile extends ConsumerWidget {
  const _JobTile({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(workspaceSessionProvider);
    final job = ref.watch(
      workspaceStateProvider.select(
        (value) =>
            value.value?.snapshot.jobs.where((job) => job.id == id).firstOrNull,
      ),
    );
    if (job == null) return const SizedBox();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(job.name)),
                Text(_status(context, job.status)),
              ],
            ),
            if (!job.terminal) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                child: LinearProgressIndicator(
                  semanticsLabel:
                      '${job.name}，${_status(context, job.status)}，'
                      '${job.indeterminate || job.totalBytes == null || job.totalBytes == 0 ? context.l10n.indeterminateProgress : '${context.l10n.byteCount(job.processedBytes)} / ${context.l10n.byteCount(job.totalBytes!)}'}',
                  value:
                      job.indeterminate ||
                          job.totalBytes == null ||
                          job.totalBytes == 0
                      ? null
                      : (job.processedBytes / job.totalBytes!).clamp(0, 1),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${context.l10n.byteCount(job.processedBytes)}${job.totalBytes == null ? '' : ' / ${context.l10n.byteCount(job.totalBytes!)}'}',
            ),
            if (job.error != null)
              Text(
                job.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (!job.terminal && job.status != JobStatus.cancelling)
                  TextButton(
                    onPressed: () => session.cancelJob(job.id),
                    child: Text(context.l10n.cancelJob),
                  ),
                if (job.status == JobStatus.failed ||
                    job.status == JobStatus.interrupted ||
                    job.status == JobStatus.cancelled)
                  TextButton(
                    onPressed: () {
                      final asset = session.state.snapshot.assets
                          .where((asset) => asset.id == job.assetId)
                          .firstOrNull;
                      if (job.kind == JobKind.thumbnail &&
                          asset?.kind == MediaKind.video) {
                        unawaited(retryVideoThumbnail(context, ref, asset!));
                      } else {
                        unawaited(session.retryJob(job.id));
                      }
                    },
                    child: Text(context.l10n.retryJob),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoTitleDialog extends StatefulWidget {
  const _TodoTitleDialog({required this.title});
  final String title;
  @override
  State<_TodoTitleDialog> createState() => _TodoTitleDialogState();
}

class _TodoTitleDialogState extends State<_TodoTitleDialog> {
  late final _controller = TextEditingController(text: widget.title);
  String? _error;

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.todoNameRequired);
      return;
    }
    Navigator.pop(context, title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.renameTodo),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: context.l10n.todoName,
        errorText: _error,
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(context.l10n.confirm)),
    ],
  );
}
