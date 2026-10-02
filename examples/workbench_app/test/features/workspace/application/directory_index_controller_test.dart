import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';
import 'package:workbench_app/features/workspace/domain/directory_selection.dart';
import 'package:workbench_app/features/workspace/presentation/providers/directory_index_providers.dart';

void main() {
  test('selection scans, refresh reuses metadata and cancellation preserves completed entries', () async {
    final source = _Source();
    final picker = _Picker(source);
    final container = ProviderContainer.test(
      overrides: [directoryIndexPickerProvider.overrideWithValue(picker)],
    );
    final keep = container.listen(directoryIndexControllerProvider, (_, _) {});
    addTearDown(keep.close);
    final controller = container.read(
      directoryIndexControllerProvider.notifier,
    );
    await controller.choose();
    expect(
      container.read(directoryIndexControllerProvider).result!.entries.keys,
      ['entry'],
    );
    await controller.refresh();
    expect(source.inspections, 1);
    expect(
      container.read(directoryIndexControllerProvider).progress!.reused,
      1,
    );
    source.fingerprintGate = Completer<DirectoryFingerprint>();
    source.started = Completer<void>();
    final pending = controller.refresh();
    await source.started!.future;
    var released = false;
    final cancelled = controller.cancel().then((_) => released = true);
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);
    source.fingerprintGate!.complete(
      DirectoryFingerprint(byteLength: 10, modifiedAt: DateTime.utc(2026)),
    );
    await cancelled;
    await pending;
    final state = container.read(directoryIndexControllerProvider);
    expect(state.result!.status, DirectoryIndexStatus.cancelled);
    expect(state.result!.entries.keys, ['entry']);
    expect(state.busy, isFalse);
    picker.cancel = true;
    await controller.choose();
    expect(
      container.read(directoryIndexControllerProvider).result,
      same(state.result),
    );
  });

  test('late picker results after disposal never start directory IO', () async {
    final source = _Source();
    final picker = _Picker(source)..gate = Completer<DirectorySelection?>();
    final container = ProviderContainer(
      overrides: [directoryIndexPickerProvider.overrideWithValue(picker)],
    );
    container.listen(directoryIndexControllerProvider, (_, _) {});
    final pending = container
        .read(directoryIndexControllerProvider.notifier)
        .choose();
    container.dispose();
    picker.gate!.complete(picker.selection);
    await pending;
    expect(source.enumerations, 0);
  });
}

final class _Picker implements DirectoryIndexPicker {
  _Picker(_Source source)
    : selection = DirectorySelection(
        label: 'Folder',
        identity: 'test',
        source: source,
      );
  final DirectorySelection selection;
  bool cancel = false;
  Completer<DirectorySelection?>? gate;
  @override
  Future<DirectorySelection?> pick() async =>
      gate?.future ?? (cancel ? null : selection);
}

final class _Source implements DirectoryIndexSource {
  int inspections = 0;
  int enumerations = 0;
  Completer<DirectoryFingerprint>? fingerprintGate;
  Completer<void>? started;
  @override
  Stream<DirectoryCandidate> enumerate() async* {
    enumerations++;
    yield const DirectoryCandidate(key: 'entry', name: 'Entry');
  }

  @override
  Future<DirectoryFingerprint> fingerprint(DirectoryCandidate candidate) async {
    started?.complete();
    return fingerprintGate?.future ??
        DirectoryFingerprint(byteLength: 10, modifiedAt: DateTime.utc(2026));
  }

  @override
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  ) async {
    inspections++;
    return IndexedFile(
      key: candidate.key,
      name: candidate.name,
      fingerprint: fingerprint,
      fileType: 'txt',
    );
  }
}
