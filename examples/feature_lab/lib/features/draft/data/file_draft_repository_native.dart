import 'dart:io';

import 'package:feature_lab/features/draft/domain/draft_repository.dart';
import 'package:koi_core/koi_core.dart';

/// Host supplies a path in its own application data directory.
/// One repository owns a file; saves are serialized before replacing it.
final class FileDraftRepository implements DraftRepository {
  FileDraftRepository(String path) : _file = File(path);
  final File _file;
  Future<void> _pending = Future<void>.value();

  @override
  FutureResult<String> read() async {
    try {
      await _pending;
      return success(await _file.exists() ? await _file.readAsString() : '');
    } catch (error, trace) {
      return failure(
        AppFailure.unknown(
          message: 'Unable to read draft',
          error: error,
          stackTrace: trace,
        ),
      );
    }
  }

  @override
  FutureResult<void> save(String text) {
    final result = _pending.then((_) => _save(text));
    _pending = result.then((_) {});
    return result;
  }

  FutureResult<void> _save(String text) async {
    final temporary = File('${_file.path}.pending');
    try {
      await _file.parent.create(recursive: true);
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(_file.path);
      return success(null);
    } catch (error, trace) {
      return failure(
        AppFailure.unknown(
          message: 'Unable to save draft',
          error: error,
          stackTrace: trace,
        ),
      );
    }
  }
}
