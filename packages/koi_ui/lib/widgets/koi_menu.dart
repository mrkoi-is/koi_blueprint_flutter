import 'package:flutter/material.dart';

@immutable
class KoiMenuItem {
  const KoiMenuItem({
    required this.label,
    this.onSelected,
    this.icon,
    this.enabled = true,
    this.checked,
    this.shortcut,
  });

  final String label;
  final VoidCallback? onSelected;
  final IconData? icon;
  final bool enabled;

  /// Null is an ordinary command; true/false is a host-owned checked option.
  final bool? checked;

  /// Display hint only, as with MenuItemButton. The host owns Shortcuts/Actions
  /// so a closed menu cannot accidentally add duplicate command handlers.
  final MenuSerializableShortcut? shortcut;
}

class KoiMenu extends StatefulWidget {
  const KoiMenu({
    required this.items,
    required this.child,
    this.label = '打开菜单',
    super.key,
  });

  final List<KoiMenuItem> items;
  final Widget child;
  final String label;

  @override
  State<KoiMenu> createState() => _KoiMenuState();
}

class _KoiMenuState extends State<KoiMenu> {
  final _focus = FocusNode();
  final _controller = MenuController();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_controller.isOpen,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _controller.isOpen) _controller.close();
    },
    child: MenuAnchor(
      controller: _controller,
      childFocusNode: _focus,
      onOpen: () => setState(() {}),
      onClose: () => setState(() {}),
      menuChildren: [
        for (final item in widget.items)
          if (item.checked != null)
            CheckboxMenuButton(
              value: item.checked,
              onChanged: item.enabled && item.onSelected != null
                  ? (_) => item.onSelected!()
                  : null,
              shortcut: item.shortcut,
              trailingIcon: item.icon == null
                  ? null
                  : Icon(item.icon, size: 18),
              child: Text(item.label),
            )
          else
            MenuItemButton(
              onPressed: item.enabled ? item.onSelected : null,
              leadingIcon: item.icon == null ? null : Icon(item.icon, size: 18),
              shortcut: item.shortcut,
              child: Text(item.label),
            ),
      ],
      builder: (context, controller, child) => TextButton(
        focusNode: _focus,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Semantics(
          expanded: controller.isOpen,
          label: widget.label,
          excludeSemantics: true,
          child: widget.child,
        ),
      ),
    ),
  );
}
