import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

Future<String?> pickSetupDirectory() => getDirectoryPath();
Future<ImportedDocument?> pickIncomingDocument(String? directory) async {
  final file = await openFile(
    initialDirectory: directory,
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Text',
        extensions: ['txt', 'md'],
        mimeTypes: ['text/plain', 'text/markdown'],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 256 * 1024) {
    throw const FormatException('Text file exceeds 256 KiB');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 256 * 1024) {
    throw const FormatException('Text file exceeds 256 KiB');
  }
  return ImportedDocument(file.name, utf8.decode(bytes));
}
