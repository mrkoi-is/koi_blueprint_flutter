import 'package:feature_lab/features/draft/domain/draft_repository.dart';
import 'package:koi_core/koi_core.dart';

/// Browser storage must be supplied by the host. Never silently pretend to persist.
final class FileDraftRepository implements DraftRepository {
  FileDraftRepository(String path);

  @override
  FutureResult<String> read() async => failure(
    const AppFailure.validation(
      message: 'File drafts require a native platform; inject a browser DraftRepository',
    ),
  );

  @override
  FutureResult<void> save(String text) async => failure(
    const AppFailure.validation(
      message: 'File drafts require a native platform; inject a browser DraftRepository',
    ),
  );
}
