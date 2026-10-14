import 'package:tray_manager/tray_manager.dart' as native;
import 'package:platform_lab/features/tray/data/tray_port.dart';

TrayPort create() => NativeTrayPort();

class NativeTrayPort implements TrayPort {
  native.TrayIcon? _icon;
  native.Image? _image;
  native.Menu? _menu;
  final _items = <native.MenuItem>[];
  @override
  Future<bool> open({
    required void Function() show,
    required void Function() quit,
    String showLabel = 'Show window',
    String quitLabel = 'Quit',
  }) async {
    if (!native.TrayManager.instance.isSupported()) return false;
    _icon = native.TrayIcon.create();
    if (_icon == null) return false;
    _image = native.Image.fromBase64(_iconPng);
    if (_image == null) {
      await close();
      return false;
    }
    _icon!.icon = _image;
    _icon!.isIconTemplate = true;
    _icon!.setTooltip('Workspace');
    _icon!.addListener((event) {
      if (event is native.TrayIconClickedEvent) show();
    });
    _menu = native.Menu.create();
    if (_menu == null) {
      await close();
      return false;
    }
    for (final entry in [(showLabel, show), (quitLabel, quit)]) {
      final item = native.MenuItem.createWithLabelAndType(
        entry.$1,
        native.MenuItemType.normal,
      );
      if (item == null) {
        await close();
        return false;
      }
      item.addListener((event) {
        if (event is native.MenuItemClickedEvent) entry.$2();
      });
      _items.add(item);
      _menu!.addItem(item);
    }
    _icon!.setContextMenu(_menu);
    _icon!.setContextMenuTrigger(native.ContextMenuTrigger.rightClicked);
    if (!_icon!.setVisible(true) || !_icon!.isVisible()) {
      await close();
      return false;
    }
    return true;
  }

  @override
  Future<void> close() async {
    _icon?.setVisible(false);
    _icon?.setContextMenu(null);
    _icon?.dispose();
    _icon = null;
    _menu?.dispose();
    _menu = null;
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _image?.dispose();
    _image = null;
  }
}

const _iconPng =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAWElEQVR4nO3Q0QkAIAxDwe6/tI6gTROikEC/39GqLJtvOYKns4VlECROQ0ziYwQjDiOYcQhhBSjiLUQAVoAy/scHAngCoEK0ZgewEfCscQaCNmu8C8my622DOLVZ3umzhAAAAABJRU5ErkJggg==';
