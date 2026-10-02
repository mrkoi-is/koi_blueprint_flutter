import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/application/directory_indexer.dart';
import 'package:workbench_app/features/workspace/data/native_directory_index_source.dart';
import 'package:workbench_app/features/workspace/domain/directory_index.dart';

void main() {
  test('real directory indexing is read-only, incremental, relative and does not follow symlinks', () async {
    final root = await Directory.systemTemp.createTemp('koi_index_');
    final outside = await Directory.systemTemp.createTemp('koi_index_outside_');
    try {
      await Directory('${root.path}/nested').create();
      final text = File('${root.path}/nested/资料.txt');
      await text.writeAsString('正文');
      await File('${outside.path}/outside.txt').writeAsString('out of scope');
      if (!Platform.isWindows) {
        await Link('${root.path}/link').create(outside.path);
      }
      final source = NativeDirectoryIndexSource(
        '${root.path}${Platform.pathSeparator}',
      );
      final first = await DirectoryIndexRun(source).result;
      expect(first.entries.keys, ['nested/资料.txt']);
      expect(first.entries.values.single.fileType, 'txt');
      expect(first.entries.values.single.fingerprint.modifiedAt.isUtc, isTrue);
      await text.writeAsString('新的更多正文');
      final second = await DirectoryIndexRun(
        source,
        previous: first.entries,
      ).result;
      expect(second.progress.inspected, 1);
      expect(
        second.entries.values.single.fingerprint.byteLength,
        await text.length(),
      );
      final third = await DirectoryIndexRun(
        source,
        previous: second.entries,
      ).result;
      expect(third.progress.reused, 1);
      await expectLater(
        source.fingerprint(
          const DirectoryCandidate(key: '../outside', name: 'bad'),
        ),
        throwsArgumentError,
      );
      expect(await text.readAsString(), '新的更多正文');
    } finally {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    }
  });
}
