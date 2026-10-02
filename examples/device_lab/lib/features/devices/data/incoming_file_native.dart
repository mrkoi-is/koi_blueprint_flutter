import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:device_lab/features/devices/domain/device_contracts.dart';

Future<ImportedDocument> readIncomingFile(String path) async {
  if (Uri.tryParse(path)?.scheme == 'content') {
    final value = await const MethodChannel('koi_blueprint/incoming_files')
        .invokeMapMethod<String, Object?>('readContent', {'uri': path});
    final bytes = value?['bytes'];
    final name = value?['name'];
    if (bytes is! List<int> || name is! String || bytes.length > 256 * 1024) {
      throw const FormatException('Invalid incoming content response');
    }
    return ImportedDocument(name, utf8.decode(bytes));
  }
  final file = File(path);
  if (await file.length() > 256 * 1024) {
    throw const FormatException('文本文件最大 256 KiB');
  }
  final bytes = <int>[];
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > 256 * 1024) {
      throw const FormatException('文本文件最大 256 KiB');
    }
    bytes.addAll(chunk);
  }
  return ImportedDocument(file.uri.pathSegments.last, utf8.decode(bytes));
}
