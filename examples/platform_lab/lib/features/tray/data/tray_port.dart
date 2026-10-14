import 'package:platform_lab/features/tray/data/tray_port_stub.dart'
    if (dart.library.io) 'package:platform_lab/features/tray/data/tray_port_native.dart'
    as platform;

abstract interface class TrayPort {
  Future<bool> open({
    required void Function() show,
    required void Function() quit,
    String showLabel = 'Show window',
    String quitLabel = 'Quit',
  });
  Future<void> close();
}

TrayPort createTrayPort() => platform.create();
