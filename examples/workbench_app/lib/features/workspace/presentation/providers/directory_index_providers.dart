import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workbench_app/features/workspace/application/directory_indexer.dart';
import 'package:workbench_app/features/workspace/data/directory_index_picker.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';
import 'package:workbench_app/features/workspace/domain/directory_selection.dart';

part 'directory_index_providers.g.dart';

@riverpod
DirectoryIndexPicker directoryIndexPicker(Ref ref) =>
    createDirectoryIndexPicker();

final class DirectoryIndexViewState {
  const DirectoryIndexViewState({
    this.label,
    this.busy = false,
    this.selecting = false,
    this.result,
    this.progress,
    this.error,
  });
  final String? label;
  final bool busy;
  final bool selecting;
  final DirectoryIndexResult? result;
  final DirectoryIndexProgress? progress;
  final Object? error;
}

/// The scan owns its source and accepted IO until completion; leaving the page
/// cancels enumeration and drains IO without writing to a disposed provider.
@riverpod
class DirectoryIndexController extends _$DirectoryIndexController {
  DirectorySelection? _selection;
  DirectoryIndexRun? _run;
  @override
  DirectoryIndexViewState build() {
    ref.onDispose(() {
      final run = _run;
      if (run != null) unawaited(run.cancel());
    });
    return const DirectoryIndexViewState();
  }

  Future<void> choose() async {
    if (state.busy || state.selecting) return;
    final previous = state;
    state = DirectoryIndexViewState(
      label: previous.label,
      result: previous.result,
      selecting: true,
    );
    try {
      final selection = await ref.read(directoryIndexPickerProvider).pick();
      if (!ref.mounted) return;
      if (selection == null) {
        state = previous;
        return;
      }
      final same = selection.identity == _selection?.identity;
      _selection = selection;
      state = DirectoryIndexViewState(
        label: selection.label,
        result: same ? previous.result : null,
      );
      await _scan(same ? previous.result?.entries ?? const {} : const {});
    } catch (error) {
      if (ref.mounted) {
        state = DirectoryIndexViewState(
          label: previous.label,
          result: previous.result,
          error: error,
        );
      }
    }
  }

  Future<void> refresh() async {
    if (state.busy || state.selecting || _selection == null) return;
    await _scan(state.result?.entries ?? const {});
  }

  Future<void> _scan(Map<String, IndexedFile> previous) async {
    final selection = _selection!;
    final run = _run = DirectoryIndexRun(selection.source, previous: previous);
    state = DirectoryIndexViewState(
      label: selection.label,
      busy: true,
      result: state.result,
      progress: run.progress,
    );
    final subscription = run.changes.listen((progress) {
      if (ref.mounted) {
        state = DirectoryIndexViewState(
          label: selection.label,
          busy: true,
          result: state.result,
          progress: progress,
        );
      }
    });
    try {
      final result = await run.result;
      if (ref.mounted) {
        state = DirectoryIndexViewState(
          label: selection.label,
          result: result,
          progress: result.progress,
        );
      }
    } finally {
      await subscription.cancel();
      if (identical(_run, run)) _run = null;
    }
  }

  Future<void> cancel() async => _run?.cancel();
}
