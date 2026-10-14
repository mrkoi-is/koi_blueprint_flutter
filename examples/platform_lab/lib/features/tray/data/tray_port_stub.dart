import 'package:platform_lab/features/tray/data/tray_port.dart';

TrayPort create() => _UnsupportedTray();

class _UnsupportedTray implements TrayPort {
  @override
  Future<bool> open({
    required void Function() show,
    required void Function() quit,
    String showLabel = 'Show window',
    String quitLabel = 'Quit',
  }) async => false;
  @override
  Future<void> close() async {}
}
