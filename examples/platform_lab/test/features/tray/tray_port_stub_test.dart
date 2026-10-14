import 'package:flutter_test/flutter_test.dart';
import 'package:platform_lab/features/tray/data/tray_port_stub.dart'
    as unsupported;

void main() {
  test(
    'unsupported tray cannot hide the window or invoke exit callbacks',
    () async {
      final tray = unsupported.create();
      var shows = 0;
      var exits = 0;

      expect(
        await tray.open(show: () => shows++, quit: () => exits++),
        isFalse,
      );
      await tray.close();
      await tray.close();

      expect(shows, 0);
      expect(exits, 0);
    },
  );
}
