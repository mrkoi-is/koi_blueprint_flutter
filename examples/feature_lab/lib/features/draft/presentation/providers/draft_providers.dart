import 'package:feature_lab/features/draft/domain/draft_repository.dart';
import 'package:feature_lab/features/draft/presentation/models/draft_editor_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'draft_providers.g.dart';

@Riverpod(keepAlive: true)
DraftRepository draftRepository(Ref ref) =>
    throw UnimplementedError('Override draftRepositoryProvider at bootstrap');

@Riverpod(keepAlive: true)
DraftSubmission draftSubmission(Ref ref) => throw UnimplementedError(
  'Override draftSubmissionProvider before enabling submission',
);

@Riverpod(keepAlive: true)
class DraftController extends _$DraftController {
  int _operation = 0;
  @override
  Future<DraftEditorState> build() async {
    ++_operation;
    final result = await ref.watch(draftRepositoryProvider).read();
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
    final result = await ref.read(draftRepositoryProvider).save(previous.text);
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
        .read(draftSubmissionProvider)
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
