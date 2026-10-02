import 'package:device_lab/features/devices/domain/device_contracts.dart';

bool get canHostDevices => false;
Future<DeviceHost> startDeviceHost(
  DeviceCommandTarget target, {
  String address = '127.0.0.1',
  int port = 0,
}) => Future.error(
  UnsupportedError(
    'Browsers connect to a paired host; they do not listen for native sockets',
  ),
);
