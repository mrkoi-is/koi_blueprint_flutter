import 'package:device_lab/features/devices/domain/device_contracts.dart';

Future<ImportedDocument> readIncomingFile(String path) =>
    Future.error(UnsupportedError('浏览器不能通过外部 file URI 读取本地文件；请用文件选择器'));
