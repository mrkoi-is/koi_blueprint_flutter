import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:koi_core/koi_core.dart';

part 'draft_editor_state.freezed.dart';

@freezed
abstract class DraftEditorState with _$DraftEditorState {
  const factory DraftEditorState({
    required String text,
    @Default(false) bool isSaving,
    AppFailure? operationFailure,
  }) = _DraftEditorState;
}
