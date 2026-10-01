import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/file_selector_import_port.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

void main() {
  test(
    'picker accepts text baseline and owns actual selected XFile bytes',
    () async {
      final port = FileSelectorImportPort(
        chooseFiles: (List<XTypeGroup> types) async {
          expect(types.single.extensions, ['txt', 'md']);
          return [
            XFile.fromData(
              Uint8List.fromList([1, 2]),
              name: '真实.txt',
              path: '真实.txt',
            ),
          ];
        },
      );
      final result = await port.select(ImportKind.text) as FilesSelected;
      final source = result.files.single;
      expect(source.name, '真实.txt');
      expect(source.byteLength, 2);
      expect(await source.openRead().expand((chunk) => chunk).toList(), [1, 2]);
      await source.close();
    },
  );
  test('cancel, missing platform, unavailable capability and unexpected failure differ', () async {
    final cancelled = FileSelectorImportPort(
      chooseFiles: (types) async {
        expect(types.single.extensions, ['jpg', 'jpeg', 'png', 'mp4']);
        return [];
      },
    );
    expect(await cancelled.select(ImportKind.media), isA<ImportCancelled>());
    final missing = FileSelectorImportPort(
      chooseFiles: (_) async => throw MissingPluginException('plugin missing'),
    );
    expect(await missing.select(ImportKind.media), isA<ImportUnavailable>());
    final unsupported = FileSelectorImportPort(
      chooseFiles: (_) async => throw UnsupportedError('unsupported'),
    );
    expect(
      await unsupported.select(ImportKind.media),
      isA<ImportUnavailable>(),
    );
    final failed = FileSelectorImportPort(
      chooseFiles: (_) async => throw StateError('failed'),
    );
    expect(await failed.select(ImportKind.media), isA<ImportFailed>());
  });
}
