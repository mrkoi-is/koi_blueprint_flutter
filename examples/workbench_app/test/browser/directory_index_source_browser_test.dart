@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:workbench_app/features/workspace/application/directory_indexer.dart';
import 'package:workbench_app/features/workspace/data/directory_index_picker_web.dart';

void main() {
  test('real browser Files provide nested keys and metadata with incremental reuse', () async {
    final file = web.File(
      ['中文'.toJS].toJS,
      '资料.txt',
      web.FilePropertyBag(lastModified: 1000),
    );
    final source = WebDirectoryIndexSource({'目录/资料.txt': file});
    final first = await DirectoryIndexRun(source).result;
    expect(first.entries.keys, ['目录/资料.txt']);
    expect(first.entries.values.single.fingerprint.byteLength, 6);
    expect(
      first.entries.values.single.fingerprint.modifiedAt.millisecondsSinceEpoch,
      1000,
    );
    expect(first.entries.values.single.fileType, 'txt');
    final second = await DirectoryIndexRun(
      source,
      previous: first.entries,
    ).result;
    expect(second.progress.inspected, 0);
    expect(second.progress.reused, 1);
  });
}
