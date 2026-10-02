import 'package:workbench_app/features/workspace/domain/directory_selection.dart';

DirectoryIndexPicker createDirectoryIndexPicker() => _UnsupportedPicker();

final class _UnsupportedPicker implements DirectoryIndexPicker {
  @override
  Future<DirectorySelection?> pick() =>
      Future.error(UnsupportedError('此平台暂不支持目录选择'));
}
