import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:workbench_app/l10n/app_strings.dart';

Widget buildJobHistoryPage(BuildContext context) => const JobHistoryPage();

class JobHistoryPage extends ConsumerStatefulWidget {
  const JobHistoryPage({super.key});
  @override
  ConsumerState<JobHistoryPage> createState() => _JobHistoryPageState();
}

class _JobHistoryPageState extends ConsumerState<JobHistoryPage> {
  String _query = '';
  int _limit = 30;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final session = ref.watch(workspaceSessionProvider);
    final records =
        ref.watch(workspaceStateProvider).value?.snapshot.jobHistory ??
        session.state.snapshot.jobHistory;
    final matching = records.reversed
        .where(
          (job) => '${job.name} ${job.id}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(strings.historyTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(labelText: strings.historySearch),
              onChanged: (query) => setState(() {
                _query = query;
                _limit = 30;
              }),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          TextButton(
            onPressed: records.isEmpty
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(strings.historyClearConfirm),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(strings.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(strings.historyClear),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) {
                      return;
                    }
                    final result = await session.clearJobHistory();
                    if (mounted) {
                      setState(
                        () => _error = result.succeeded ? null : result.error,
                      );
                    }
                  },
            child: Text(strings.historyClear),
          ),
          Expanded(
            child: matching.isEmpty
                ? Center(child: Text(strings.historyEmpty))
                : ListView.builder(
                    itemCount: matching.length > _limit
                        ? _limit + 1
                        : matching.length,
                    itemBuilder: (context, index) {
                      if (index == _limit) {
                        return TextButton(
                          onPressed: () => setState(() => _limit += 30),
                          child: Text(strings.diagMore),
                        );
                      }
                      final job = matching[index];
                      final current = session.state.snapshot.jobs
                          .where((value) => value.id == job.id)
                          .firstOrNull;
                      final canRetry =
                          current != null &&
                          current.currentAttempt == job.currentAttempt &&
                          (current.status == JobStatus.failed ||
                              current.status == JobStatus.interrupted ||
                              current.status == JobStatus.cancelled);
                      return ListTile(
                        key: ValueKey('${job.id}:${job.currentAttempt}'),
                        title: Text(job.name),
                        subtitle: Text(
                          '${job.id}\n${strings.historyAttempt(job.currentAttempt)} · ${job.status.name}\n${job.startedAt?.toLocal() ?? '—'} → ${job.finishedAt?.toLocal() ?? '—'}\n${job.error ?? ''}',
                        ),
                        trailing: canRetry
                            ? IconButton(
                                tooltip: strings.retry,
                                icon: const Icon(Icons.refresh),
                                onPressed: () async {
                                  try {
                                    await session.retryJob(job.id);
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = '$error');
                                    }
                                  }
                                },
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
