import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:network_lab/features/images/domain/image_source.dart';

LocalImageReader createLocalImageReader() => FileImageReader();

final class FileImageReader implements LocalImageReader {
  bool _closed = false;
  @override
  Future<Uint8List> read(String key, {required int maxBytes}) async {
    if (_closed) throw StateError('Local reader closed');
    final file = File(key);
    if (await file.length() > maxBytes) {
      throw StateError('Local image exceeds byte budget');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw StateError('Local image exceeds byte budget');
      }
      bytes.add(chunk);
    }
    if (_closed) throw StateError('Local reader closed');
    return bytes.takeBytes();
  }

  @override
  Future<String?> pick({required int maxBytes}) async {
    if (_closed) throw StateError('Local reader closed');
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
        ),
      ],
    );
    if (file == null || _closed) return null;
    if (await file.length() > maxBytes) {
      throw StateError('Local image exceeds byte budget');
    }
    return file.path;
  }

  @override
  void close() {
    _closed = true;
  }
}
