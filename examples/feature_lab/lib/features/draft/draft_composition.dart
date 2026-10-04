// Host assembly entry: implementations and injectable declarations.
import 'package:feature_lab/features/draft/domain/draft_repository.dart';
import 'package:feature_lab/features/draft/presentation/providers/draft_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

export 'data/file_draft_repository.dart';
export 'presentation/providers/draft_providers.dart';

/// Bind every draft in one session and explicitly own its editor family.
///
/// Use these overrides on the session's ProviderScope. Explicitly overriding
/// the controller family also isolates editors already read in a parent scope;
/// keepAlive and automatic scoping alone cannot guarantee that ownership.
/// Destroying the session scope drops edits but does not dispose borrowed ports.
List<Override> draftSessionOverrides({
  required Map<String, DraftRepository> repositories,
  Map<String, DraftSubmission> submissions = const {},
}) => [
  draftRepositoryProvider.overrideWith(
    (ref, draftId) =>
        repositories[draftId] ??
        (throw StateError('No draft repository for $draftId in this session')),
  ),
  draftSubmissionProvider.overrideWith(
    (ref, draftId) =>
        submissions[draftId] ??
        (throw StateError('No draft submission for $draftId in this session')),
  ),
  draftControllerProvider.overrideWith2((_) => DraftController()),
];
