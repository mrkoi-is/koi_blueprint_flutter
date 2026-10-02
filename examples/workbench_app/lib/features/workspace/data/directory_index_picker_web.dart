import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/domain/directory_index.dart';
import 'package:workbench_app/features/workspace/domain/directory_selection.dart';

DirectoryIndexPicker createDirectoryIndexPicker() => _WebPicker();

final class _WebPicker implements DirectoryIndexPicker {
  @override
  Future<DirectorySelection?> pick() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true;
    input.setAttribute('webkitdirectory', '');
    final result = Completer<DirectorySelection?>();
    void finish(DirectorySelection? selection) {
      if (result.isCompleted) return;
      input.remove();
      input.onchange = null;
      input.oncancel = null;
      result.complete(selection);
    }

    input.oncancel = ((web.Event _) => finish(null)).toJS;
    input.onchange = ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }
      final selected = <String, web.File>{};
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i)!;
        selected[file.webkitRelativePath.isEmpty
                ? file.name
                : file.webkitRelativePath] =
            file;
      }
      final label = selected.keys.first.split('/').first;
      finish(
        DirectorySelection(
          label: label,
          identity: label,
          source: WebDirectoryIndexSource(selected),
        ),
      );
    }).toJS;
    input.style.display = 'none';
    web.document.body!.appendChild(input);
    input.click();
    return result.future;
  }
}

/// Browser-selected Files are retained only for the current index session.
final class WebDirectoryIndexSource implements DirectoryIndexSource {
  WebDirectoryIndexSource(Map<String, web.File> files)
    : _files = Map.unmodifiable(files);
  final Map<String, web.File> _files;
  @override
  Stream<DirectoryCandidate> enumerate() async* {
    for (final entry in _files.entries) {
      yield DirectoryCandidate(key: entry.key, name: entry.value.name);
    }
  }

  @override
  Future<DirectoryFingerprint> fingerprint(DirectoryCandidate candidate) async {
    final file = _files[candidate.key]!;
    return DirectoryFingerprint(
      byteLength: file.size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        file.lastModified,
        isUtc: true,
      ),
    );
  }

  @override
  Future<IndexedFile> inspect(
    DirectoryCandidate candidate,
    DirectoryFingerprint fingerprint,
  ) async => IndexedFile(
    key: candidate.key,
    name: candidate.name,
    fingerprint: fingerprint,
    fileType: candidate.name.contains('.')
        ? candidate.name.split('.').last.toLowerCase()
        : 'unknown',
  );
}
