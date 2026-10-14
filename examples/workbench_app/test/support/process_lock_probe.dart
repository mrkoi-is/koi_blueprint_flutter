import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File('${args.single}/workspace.lock')
      .open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive, 0, 1);
    stdout.writeln('acquired');
    await file.unlock(0, 1);
  } on FileSystemException {
    stdout.writeln('busy');
  } finally {
    await file.close();
  }
}
