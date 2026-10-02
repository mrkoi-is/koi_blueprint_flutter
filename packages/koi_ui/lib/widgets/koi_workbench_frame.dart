import 'package:koi_ui/widgets/koi_menu.dart';
import 'package:koi_ui/l10n/koi_ui_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:koi_ui/theme/koi_theme_tokens.dart';
import 'package:koi_ui/widgets/koi_panel_icon.dart';
import 'package:koi_ui/widgets/koi_resizable_split_view.dart';

/// Presentation-only panel commands shared by Flutter and native toolbars.
/// One controller belongs to one frame. The host owns its lifetime.
class KoiWorkbenchController extends ChangeNotifier {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _expanded = false;
  bool _hasSidebar = false;
  bool _hasDetail = false;
  bool _sidebarVisible = true;
  bool _detailVisible = true;
  bool _drawerOpen = false;
  bool _endDrawerOpen = false;

  bool get canToggleSidebar => _hasSidebar;
  bool get canToggleDetail => _hasDetail;
  bool get sidebarOpen =>
      _expanded ? _sidebarVisible && _hasSidebar : _drawerOpen;
  bool get detailOpen =>
      _expanded ? _detailVisible && _hasDetail : _endDrawerOpen;

  void toggleSidebar() {
    if (!_hasSidebar || _scaffoldKey.currentState == null) return;
    if (_expanded) {
      _sidebarVisible = !_sidebarVisible;
      notifyListeners();
    } else if (_drawerOpen) {
      _scaffoldKey.currentState!.closeDrawer();
    } else {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  void toggleDetail() {
    if (!_hasDetail || _scaffoldKey.currentState == null) return;
    if (_expanded) {
      _detailVisible = !_detailVisible;
      notifyListeners();
    } else if (_endDrawerOpen) {
      _scaffoldKey.currentState!.closeEndDrawer();
    } else {
      _scaffoldKey.currentState!.openEndDrawer();
    }
  }

  void _layout({
    required bool expanded,
    required bool sidebar,
    required bool detail,
  }) {
    if (_expanded == expanded &&
        _hasSidebar == sidebar &&
        _hasDetail == detail) {
      return;
    }
    _expanded = expanded;
    _hasSidebar = sidebar;
    _hasDetail = detail;
    if (expanded || !sidebar) _drawerOpen = false;
    if (expanded || !detail) _endDrawerOpen = false;
    notifyListeners();
  }

  void _drawerChanged(bool value, {bool trailing = false}) {
    if (trailing) {
      if (_endDrawerOpen == value) return;
      _endDrawerOpen = value;
    } else {
      if (_drawerOpen == value) return;
      _drawerOpen = value;
    }
    notifyListeners();
  }
}

@immutable
class KoiNavigationDestination {
  const KoiNavigationDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
}

/// A pure presentation shell. Hosts retain controllers, routes and sessions.
class KoiWorkbenchFrame extends StatefulWidget {
  const KoiWorkbenchFrame({
    required this.destinations,
    required this.selectedId,
    required this.onDestinationSelected,
    required this.body,
    this.sidebar,
    this.detail,
    this.title,
    this.showHeader = true,
    this.controller,
    this.headerLeading,
    this.headerLeadingWidth = 96,
    this.actions = const [],
    this.navigationTrailing,
    this.sidebarWidth = 280,
    this.onSidebarWidthChanged,
    this.detailWidth = 280,
    this.onDetailWidthChanged,
    super.key,
  }) : assert(destinations.length > 0);

  final List<KoiNavigationDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onDestinationSelected;
  final Widget body;
  final Widget? sidebar;
  final Widget? detail;
  final Widget? title;

  /// False means the host owns ALL toolbar controls, including drawer commands.
  final bool showHeader;
  final KoiWorkbenchController? controller;

  /// Title-bar history controls. Compact Flutter headers use the title slot.
  final Widget? headerLeading;
  final double headerLeadingWidth;
  final List<Widget> actions;

  /// Pinned below the rail destinations; shown in the compact header instead.
  final Widget? navigationTrailing;
  final double sidebarWidth;
  final ValueChanged<double>? onSidebarWidthChanged;
  final double detailWidth;
  final ValueChanged<double>? onDetailWidthChanged;

  @override
  State<KoiWorkbenchFrame> createState() => _KoiWorkbenchFrameState();
}

class _KoiWorkbenchFrameState extends State<KoiWorkbenchFrame> {
  late KoiWorkbenchController _controller;
  bool _layoutScheduled = false;
  ({bool expanded, bool sidebar, bool detail})? _pendingLayout;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? KoiWorkbenchController();
    _controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(KoiWorkbenchFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_rebuild);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? KoiWorkbenchController();
      _controller.addListener(_rebuild);
    }
  }

  void _reportLayout(bool expanded) {
    _pendingLayout = (
      expanded: expanded,
      sidebar: widget.sidebar != null,
      detail: widget.detail != null,
    );
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      final layout = _pendingLayout!;
      _controller._layout(
        expanded: layout.expanded,
        sidebar: layout.sidebar,
        detail: layout.detail,
      );
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final expanded = constraints.maxWidth >= 1024;
      _reportLayout(expanded);
      final tokens = KoiThemeTokens.of(context);
      final chromeBackground = tokens.chromeBackground;
      final separatorColor = Theme.of(context).colorScheme.onSurface
          .withValues(alpha: .06);
      final selected = widget.destinations.indexWhere(
        (item) => item.id == widget.selectedId,
      );
      final selectedIndex = selected < 0 ? 0 : selected;
      void select(int index) =>
          widget.onDestinationSelected(widget.destinations[index].id);
      Widget content = widget.body;
      if (expanded && widget.detail != null && _controller._detailVisible) {
        content = KoiResizableSplitView(
          primary: _panelSurface(widget.detail!, 'detail'),
          secondary: content,
          primaryOnTrailing: true,
          resizeLabel: KoiUiStrings.of(context).resizeDetail,
          width: widget.detailWidth,
          onWidthChanged: widget.onDetailWidthChanged,
          minSecondaryWidth: 320,
        );
      }
      if (expanded && widget.sidebar != null && _controller._sidebarVisible) {
        content = KoiResizableSplitView(
          primary: _panelSurface(widget.sidebar!, 'sidebar'),
          secondary: content,
          width: widget.sidebarWidth,
          onWidthChanged: widget.onSidebarWidthChanged,
          minSecondaryWidth:
              widget.detail == null || !_controller._detailVisible ? 320 : 560,
        );
      }
      content = Padding(
        padding: const EdgeInsets.all(KoiWorkbenchMetrics.contentInset),
        child: Material(
          key: const ValueKey('koi-workbench-content-surface'),
          color: tokens.contentBackground,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              KoiWorkbenchMetrics.contentRadius,
            ),
            side: BorderSide(color: separatorColor),
          ),
          clipBehavior: Clip.antiAlias,
          // Nested route overlays may block earlier semantics within this
          // region, but must not hide the global navigation outside it.
          child: Semantics(container: true, child: content),
        ),
      );
      if (!compact) {
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NavigationRail(
              backgroundColor: chromeBackground,
              minWidth: KoiWorkbenchMetrics.railWidth,
              groupAlignment: -1,
              scrollable: true,
              trailingAtBottom: true,
              trailing: widget.navigationTrailing == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(bottom: KoiSpace.sm),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        child: widget.navigationTrailing,
                      ),
                    ),
              indicatorColor: Colors.transparent,
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KoiRadius.small),
              ),
              selectedIndex: selected < 0 ? null : selectedIndex,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.none,
              destinations: [
                for (final destination in widget.destinations)
                  NavigationRailDestination(
                    // Material 3's indicator and destination spacing total
                    // 44 px. Keep primary navigation targets at 48 px in
                    // both densities.
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    icon: Icon(destination.icon),
                    selectedIcon: Container(
                      width: KoiWorkbenchMetrics.navigationIndicatorSize,
                      height: KoiWorkbenchMetrics.navigationIndicatorSize,
                      decoration: BoxDecoration(
                        color: tokens.selectedBackground,
                        borderRadius: BorderRadius.circular(KoiRadius.small),
                      ),
                      child: Icon(destination.selectedIcon ?? destination.icon),
                    ),
                    label: Text(destination.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, thickness: 1, color: separatorColor),
            Expanded(child: content),
          ],
        );
      }
      final drawerWidth = math.min(360.0, constraints.maxWidth * .85);
      return KoiMenuLayout(
        width: constraints.maxWidth,
        child: Scaffold(
          backgroundColor: chromeBackground,
          key: _controller._scaffoldKey,
          onDrawerChanged: _controller._drawerChanged,
          onEndDrawerChanged: (open) =>
              _controller._drawerChanged(open, trailing: true),
          appBar: widget.showHeader
              ? AppBar(
                  backgroundColor: chromeBackground,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: compact && widget.headerLeading != null
                      ? widget.headerLeading
                      : widget.title,
                  centerTitle: false,
                  titleSpacing: compact ? 0 : null,
                  automaticallyImplyLeading: false,
                  leading: compact
                      ? (widget.sidebar == null ? null : _sidebarButton())
                      : Row(
                          children: [
                            if (widget.headerLeading != null)
                              SizedBox(
                                width: widget.headerLeadingWidth,
                                child: widget.headerLeading,
                              ),
                            if (widget.sidebar != null) _sidebarButton(),
                          ],
                        ),
                  leadingWidth: compact
                      ? null
                      : (widget.headerLeading == null
                                ? 0
                                : widget.headerLeadingWidth) +
                            (widget.sidebar == null ? 0 : 48),
                  actions: [
                    ...widget.actions,
                    if (compact && widget.navigationTrailing != null)
                      widget.navigationTrailing!,
                    if (widget.detail != null) _detailButton(),
                  ],
                )
              : null,
          drawer: !expanded && widget.sidebar != null
              ? Drawer(
                  width: drawerWidth,
                  backgroundColor: tokens.panelBackground,
                  child: SafeArea(
                    child: _panelSurface(widget.sidebar!, 'sidebar'),
                  ),
                )
              : null,
          endDrawer: !expanded && widget.detail != null
              ? Drawer(
                  width: drawerWidth,
                  backgroundColor: tokens.panelBackground,
                  child: SafeArea(
                    child: _panelSurface(widget.detail!, 'detail'),
                  ),
                )
              : null,
          body: SafeArea(top: false, child: content),
          bottomNavigationBar:
              compact &&
                  (widget.destinations.length >= 2 ||
                      (!widget.showHeader && widget.navigationTrailing != null))
              ? Row(
                  children: [
                    if (widget.destinations.length >= 2)
                      Expanded(
                        child: NavigationBar(
                          backgroundColor: chromeBackground,
                          selectedIndex: selectedIndex,
                          onDestinationSelected: select,
                          labelBehavior: NavigationDestinationLabelBehavior
                              .onlyShowSelected,
                          destinations: [
                            for (final destination in widget.destinations)
                              NavigationDestination(
                                icon: Icon(destination.icon),
                                selectedIcon: Icon(
                                  destination.selectedIcon ?? destination.icon,
                                ),
                                label: destination.label,
                              ),
                          ],
                        ),
                      ),
                    if (widget.destinations.length < 2) const Spacer(),
                    if (!widget.showHeader && widget.navigationTrailing != null)
                      SafeArea(top: false, child: widget.navigationTrailing!),
                  ],
                )
              : null,
        ),
      );
    },
  );

  Widget _panelSurface(Widget child, String name) => Material(
    key: ValueKey('koi-workbench-$name-surface'),
    color: KoiThemeTokens.of(context).panelBackground,
    surfaceTintColor: Colors.transparent,
    child: child,
  );

  ButtonStyle _panelStyle() {
    final colors = Theme.of(context).colorScheme;
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onSurface
            : colors.onSurfaceVariant,
      ),
    );
  }

  Widget _sidebarButton() => IconButton(
    style: _panelStyle(),
    tooltip: KoiUiStrings.of(context).toggleSidebar,
    isSelected: _controller.sidebarOpen,
    onPressed: _controller.toggleSidebar,
    icon: const KoiPanelIcon(),
  );

  Widget _detailButton() => IconButton(
    style: _panelStyle(),
    tooltip: KoiUiStrings.of(context).toggleDetail,
    isSelected: _controller.detailOpen,
    onPressed: _controller.toggleDetail,
    icon: const KoiPanelIcon(trailing: true),
  );
}
