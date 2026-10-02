import 'package:device_lab/features/devices/domain/device_contracts.dart';

DeviceDiscovery createDeviceDiscovery() => _ManualOnlyDiscovery();

final class _ManualOnlyDiscovery implements DeviceDiscovery {
  @override
  Stream<List<DiscoveredDevice>> get changes => const Stream.empty();
  @override
  Future<void> start() =>
      Future.error(UnsupportedError('浏览器无法扫描 Bonjour，请输入设备地址'));
  @override
  Future<void> close() async {}
}

Future<DeviceAdvertisement> advertiseDevice(String name, int port) =>
    Future.error(UnsupportedError('浏览器不能发布局域网服务'));
