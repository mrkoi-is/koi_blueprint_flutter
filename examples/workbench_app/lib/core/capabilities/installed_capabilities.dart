// Managed by blueprint capability add. User entries belong in app_capabilities.dart.
import 'package:workbench_app/core/capabilities/app_capability.dart';
import 'package:workbench_app/core/capabilities/capability_lifecycle.dart';
import 'package:workbench_app/l10n/generated/app_localizations.dart';
import 'package:workbench_app/features/workspace/presentation/screens/directory_index_page.dart'
    as directory_index;
import 'package:workbench_app/features/workspace/presentation/screens/bulk_documents_page.dart'
    as bulk_selection;
import 'package:workbench_app/features/workspace/presentation/screens/job_history_page.dart'
    as task_history;

final installedCapabilities = <AppCapabilityPage>[
  AppCapabilityPage(
    id: 'directory-index',
    title: '资料索引',
    builder: directory_index.buildDirectoryIndexPage,
    titleBuilder: (context) =>
        AppLocalizations.of(context)!.directoryIndexTitle,
  ),
  AppCapabilityPage(
    id: 'bulk-selection',
    title: '批量选择',
    builder: bulk_selection.buildBulkDocumentsPage,
    titleBuilder: (context) => AppLocalizations.of(context)!.bulkDocumentsTitle,
  ),
  AppCapabilityPage(
    id: 'task-history',
    title: '任务历史',
    builder: task_history.buildJobHistoryPage,
    titleBuilder: (context) => AppLocalizations.of(context)!.historyTitle,
  ),
];

Future<void> initializeInstalledCapabilities() async {}

Future<bool> prepareInstalledCapabilities() async {
  return CapabilityLifecycle.instance.prepare();
}

Future<void> disposeInstalledCapabilities() =>
    CapabilityLifecycle.instance.close();
