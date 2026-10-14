import 'package:flutter/services.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Test-only input adapter. Storage, decode, preview, Player and disposal stay real.
/// This intentionally does not claim to exercise an operating-system file picker.
class FixtureImportPort implements FileImportPort {
  final sources = <FixtureImportSource>[];

  @override
  Future<FileImportResult> select(ImportKind kind) async {
    final names = kind == ImportKind.text
        ? ['中文资料.md']
        : ['gradient.png', 'gradient.jpg', 'landscape.mp4', 'portrait.mp4'];
    final selected = <FixtureImportSource>[];
    for (final name in names) {
      final bytes = await loadFixture(name);
      final source = FixtureImportSource(name, bytes);
      selected.add(source);
      sources.add(source);
    }
    return FilesSelected(selected);
  }
}

Future<Uint8List> loadFixture(String name) async {
  final data = await rootBundle.load('assets/fixtures/$name');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class FixtureImportSource implements ImportSource {
  FixtureImportSource(this.name, this.bytes);
  @override
  final String name;
  final Uint8List bytes;
  bool closed = false;
  @override
  int get byteLength => bytes.length;
  @override
  Stream<List<int>> openRead() async* {
    if (closed) throw StateError('Fixture source is closed');
    for (var start = 0; start < bytes.length; start += 4096) {
      if (closed) throw StateError('Fixture read after close');
      final end = start + 4096 < bytes.length ? start + 4096 : bytes.length;
      yield Uint8List.sublistView(bytes, start, end);
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
