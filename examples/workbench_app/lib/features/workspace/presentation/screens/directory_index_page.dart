import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';
import 'package:workbench_app/features/workspace/presentation/providers/directory_index_providers.dart';
import 'package:workbench_app/l10n/app_strings.dart';

Widget buildDirectoryIndexPage(BuildContext context) =>
    const DirectoryIndexPage();

class DirectoryIndexPage extends ConsumerWidget {
  const DirectoryIndexPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directoryIndexControllerProvider);
    final controller = ref.read(directoryIndexControllerProvider.notifier);
    final strings = context.l10n;
    final result = state.result;
    final progress = state.progress;
    final entries = result?.entries.values.toList() ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(strings.directoryIndexTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.directoryIndexHint),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: state.busy || state.selecting
                            ? null
                            : controller.choose,
                        icon: const Icon(Icons.folder_open),
                        label: Text(strings.chooseDirectory),
                      ),
                      OutlinedButton(
                        onPressed:
                            state.busy || state.selecting || state.label == null
                            ? null
                            : controller.refresh,
                        child: Text(strings.rescanDirectory),
                      ),
                      if (state.busy)
                        OutlinedButton(
                          onPressed: controller.cancel,
                          child: Text(strings.cancel),
                        ),
                    ],
                  ),
                  if (state.label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        state.label!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  if (progress != null)
                    Text(
                      strings.directoryIndexProgress(
                        progress.visited,
                        progress.reused,
                        progress.failures,
                      ),
                    ),
                  if (result != null && !state.busy)
                    Text(switch (result.status) {
                      DirectoryIndexStatus.completed =>
                        result.issues.isEmpty
                            ? strings.directoryIndexCompleted
                            : strings.directoryIndexFailed,
                      DirectoryIndexStatus.cancelled =>
                        strings.directoryIndexCancelled,
                      DirectoryIndexStatus.failed =>
                        strings.directoryIndexFailed,
                    }),
                  if (state.error != null)
                    SelectableText(
                      '${state.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (result?.issues.isNotEmpty == true)
                    Text(
                      result!.issues.first.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            if (state.busy || state.selecting) const LinearProgressIndicator(),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(strings.directoryIndexEmpty))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          key: ValueKey(entry.key),
                          title: Text(entry.name),
                          subtitle: Text(entry.key),
                          trailing: Text(
                            strings.byteCount(entry.fingerprint.byteLength),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
