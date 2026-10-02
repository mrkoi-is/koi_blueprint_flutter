import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koi_ui/l10n/koi_ui_strings.dart';

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

enum KoiMenuPresentation { adaptive, anchored, sheet }

/// Pass the width of a layout region, not the width of its menu trigger.
class KoiMenuLayout extends InheritedWidget {
  const KoiMenuLayout({required this.width, required super.child, super.key});
  final double width;
  static double widthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KoiMenuLayout>()?.width ??
      MediaQuery.sizeOf(context).width;
  @override
  bool updateShouldNotify(KoiMenuLayout oldWidget) => width != oldWidget.width;
}

class KoiMenu extends StatefulWidget {
  const KoiMenu({
    required this.items,
    required this.child,
    this.label,
    this.presentation = KoiMenuPresentation.adaptive,
    super.key,
  });
  final List<KoiMenuItem> items;
  final Widget child;
  final String? label;
  final KoiMenuPresentation presentation;
  @override
  State<KoiMenu> createState() => _KoiMenuState();
}

class _KoiMenuState extends State<KoiMenu> {
  final _focus = FocusNode();
  final _controller = MenuController();
  bool _sheetOpen = false;
  ModalRoute<void>? _sheetRoute;
  NavigatorState? _sheetNavigator;
  bool get _isOpen => _sheetOpen || _controller.isOpen;

  @override
  void dispose() {
    final route = _sheetRoute;
    final navigator = _sheetNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    _focus.dispose();
    super.dispose();
  }

  Future<void> _showSheet() async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          _sheetRoute = ModalRoute.of<void>(sheetContext);
          _sheetNavigator = Navigator.of(sheetContext);
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(sheetContext).pop(),
            },
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in widget.items)
                          ListTile(
                            enabled: item.enabled && item.onSelected != null,
                            minTileHeight: 48,
                            leading: item.checked != null
                                ? Icon(item.checked! ? Icons.check : null)
                                : item.icon == null
                                ? null
                                : Icon(item.icon),
                            title: Semantics(
                              checked: item.checked,
                              child: Text(item.label),
                            ),
                            onTap: item.enabled && item.onSelected != null
                                ? () {
                                    Navigator.of(sheetContext).pop();
                                    item.onSelected!();
                                  }
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _sheetRoute = null;
      _sheetNavigator = null;
      if (mounted) {
        setState(() => _sheetOpen = false);
        if (ModalRoute.of(context)?.isCurrent ?? true) _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = switch (widget.presentation) {
      KoiMenuPresentation.sheet => true,
      KoiMenuPresentation.anchored => false,
      KoiMenuPresentation.adaptive => KoiMenuLayout.widthOf(context) < 600,
    };
    return PopScope<Object?>(
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
                leadingIcon: item.icon == null
                    ? null
                    : Icon(item.icon, size: 18),
                shortcut: item.shortcut,
                child: Text(item.label),
              ),
        ],
        builder: (context, controller, child) => TextButton(
          focusNode: _focus,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else if (sheet) {
              _showSheet();
            } else {
              controller.open();
            }
          },
          child: Semantics(
            expanded: _isOpen,
            label: widget.label ?? KoiUiStrings.of(context).openMenu,
            excludeSemantics: true,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
