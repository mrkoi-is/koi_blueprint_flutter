import 'package:feature_lab/features/draft/domain/draft_repository.dart';
import 'package:feature_lab/features/draft/presentation/models/draft_editor_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'draft_providers.g.dart';

@Riverpod(keepAlive: true, dependencies: [])
DraftRepository draftRepository(Ref ref, {String draftId = 'default'}) =>
    throw UnimplementedError('Override draftRepositoryProvider at bootstrap');

@Riverpod(keepAlive: true, dependencies: [])
DraftSubmission draftSubmission(Ref ref, {String draftId = 'default'}) =>
    throw UnimplementedError(
      'Override draftSubmissionProvider before enabling submission',
    );

@Riverpod(keepAlive: true, dependencies: [draftRepository, draftSubmission])
class DraftController extends _$DraftController {
  int _operation = 0;
  // draftSessionOverrides places this keepAlive family in its owning session.
  // Scoped dependencies also declare which ports can be rebound. Destroying the
  // session scope releases every editor instead of retaining it at the app root.
  @override
  /// Each open route passes a stable editorId so two editors can edit the same
  /// persisted draft independently while that session remains open.
  Future<DraftEditorState> build({
    String draftId = 'default',
    String editorId = 'primary',
  }) async {
    ++_operation;
    final result = await ref
        .watch(draftRepositoryProvider(draftId: draftId))
        .read();
    return result.fold(
      (error) => throw error,
      (text) => DraftEditorState(text: text),
    );
  }

  void edit(String text) {
    ++_operation;
    state = AsyncData(DraftEditorState(text: text));
  }

  Future<void> save() async {
    if (!state.hasValue) return;
    final operation = ++_operation;
    final previous = state.requireValue;
    state = AsyncData(
      previous.copyWith(isSaving: true, operationFailure: null),
    );
    final result = await ref
        .read(draftRepositoryProvider(draftId: draftId))
        .save(previous.text);
    if (!ref.mounted || operation != _operation) return;
    state = AsyncData(
      result.fold(
        (error) => previous.copyWith(isSaving: false, operationFailure: error),
        (_) => previous.copyWith(isSaving: false, operationFailure: null),
      ),
    );
  }

  Future<void> submit() async {
    if (!state.hasValue) return;
    final operation = ++_operation;
    final previous = state.requireValue;
    state = AsyncData(
      previous.copyWith(isSaving: true, operationFailure: null),
    );
    final result = await ref
        .read(draftSubmissionProvider(draftId: draftId))
        .submit(previous.text);
    if (!ref.mounted || operation != _operation) return;
    state = AsyncData(
      result.fold(
        (error) => previous.copyWith(isSaving: false, operationFailure: error),
        (_) => previous.copyWith(isSaving: false, operationFailure: null),
      ),
    );
  }
}
