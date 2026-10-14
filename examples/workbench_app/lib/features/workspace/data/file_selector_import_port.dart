import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'package:workbench_app/features/workspace/domain/workspace_models.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';
import 'package:workbench_app/features/workspace/data/selected_source_cleanup.dart';

final class FileSelectorImportPort implements FileImportPort {
  const FileSelectorImportPort({this._chooseFiles});
  final Future<List<XFile>> Function(List<XTypeGroup>)? _chooseFiles;

  @override
  Future<FileImportResult> select(ImportKind kind) async {
    var selected = <XFile>[];
    var transferred = false;
    try {
      final types = [
        kind == ImportKind.text
            ? const XTypeGroup(
                label: '文本资料',
                extensions: ['txt', 'md'],
                mimeTypes: ['text/plain', 'text/markdown'],
                uniformTypeIdentifiers: [
                  'public.plain-text',
                  'net.daringfireball.markdown',
                ],
              )
            : const XTypeGroup(
                label: '图片与视频',
                extensions: ['jpg', 'jpeg', 'png', 'mp4'],
                mimeTypes: ['image/jpeg', 'image/png', 'video/mp4'],
                uniformTypeIdentifiers: [
                  'public.jpeg',
                  'public.png',
                  'public.mpeg-4',
                ],
              ),
      ];
      selected =
          await (_chooseFiles?.call(types) ??
              openFiles(acceptedTypeGroups: types));
      final files = selected;
      if (files.isEmpty) return const ImportCancelled();
      final sources = <ImportSource>[];
      for (final file in files) {
        sources.add(_SelectedSource(file, await file.length()));
      }
      transferred = true;
      return FilesSelected(List.unmodifiable(sources));
    } on MissingPluginException catch (error) {
      return ImportUnavailable(error.message ?? '当前环境没有文件选择器');
    } on UnsupportedError catch (error) {
      return ImportUnavailable(error.message?.toString() ?? '当前平台不能选择文件');
    } catch (error) {
      return ImportFailed('文件选择失败：$error');
    } finally {
      if (!transferred) {
        for (final file in selected) {
          releaseSelectedSource(file.path);
        }
      }
    }
  }
}

final class _SelectedSource implements ImportSource {
  const _SelectedSource(this._file, this.byteLength);
  final XFile _file;
  @override
  final int byteLength;
  @override
  String get name => _file.name;
  @override
  Stream<List<int>> openRead() => _file.openRead();
  @override
  Future<void> close() async => releaseSelectedSource(_file.path);
}
