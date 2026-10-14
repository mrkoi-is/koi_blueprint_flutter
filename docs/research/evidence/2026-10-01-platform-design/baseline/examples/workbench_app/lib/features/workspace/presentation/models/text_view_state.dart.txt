import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

part 'text_view_state.freezed.dart';

/// Equality compares document values, including equivalent post-save lists.
@freezed
abstract class TextViewState with _$TextViewState {
  const factory TextViewState({
    required List<WorkspaceDocument> documents,
    String? selectedId,
    required double sidebarWidth,
  }) = _TextViewState;
}
