# Koi UI

Pure Flutter presentation components. Hosts own routes, providers, repositories,
editing controllers and media sessions.

```dart
MaterialApp(
  theme: AppTheme.build(density: KoiDensity.comfortable),
  darkTheme: AppTheme.build(
    brightness: Brightness.dark,
    density: KoiDensity.compact,
  ),
);
```

`AppTheme.light` and `AppTheme.dark` remain compatible. `KoiThemeTokens.of(context)`
also works in ordinary Material hosts. `KoiSpace` and `KoiRadius` define shared
logical-pixel dimensions.

`KoiWorkbenchFrame` adapts to its local available width: bottom navigation below
600, rail from 600, inline sidebar/details from 1024. Narrow sidebars/details use
Scaffold drawers. A host can own a stable `KoiWorkbenchController` and pass it
to the frame. Its `toggleSidebar` / `toggleDetail` commands open drawers when
narrow and toggle inline panels when wide. `canToggleSidebar`, `canToggleDetail`,
`sidebarOpen` and `detailOpen` let a native toolbar mirror the current frame.
The controller belongs to one frame and must be disposed by its creator.
`showHeader: false` means the host supplies ALL toolbar controls at every width;
there is no extra drawer toolbar. Flutter headers use directional `KoiPanelIcon`
buttons; a null `detail` removes that page's detail action. The compact navigation
bar keeps Material's default 80 height and adds the bottom safe inset once.
Settings remain reachable even when a native toolbar owns the compact header.
Pass stable external controllers to body widgets; the shell
may reparent presentation when changing layouts. `KoiResizableSplitView` needs
bounded width and height; its divider supports drag, Tab, arrows, Home and End.
`primaryOnTrailing` enables trailing-pane sizing. Physical drag and arrow-key
direction follows LTR/RTL. Compact split targets are 12 wide; comfortable
targets reserve 48 without overlapping adjacent controls. Decorative grip
transitions honor the system reduce-motion flag. The frame exposes
`sidebarWidth/onSidebarWidthChanged` and `detailWidth/onDetailWidthChanged` so
hosts can persist both panel widths. Each pane and resize handle has an
independent semantics boundary. This is necessary when a body contains a nested
Navigator: a route must not hide the rail or adjacent panes from accessibility.

The title bar and fixed icon rail share `KoiThemeTokens.chromeBackground`.
The resource sidebar and inspector use `panelBackground`; the main body uses
`contentBackground`. All stay inside one clipped, rounded container with a small
outer inset. Narrow supporting-panel drawers also use `panelBackground`. Both light and dark themes provide
distinct surfaces; ordinary Material hosts fall back to their ColorScheme.
Structural edges use a subtle color independent of control outlines. Split
dividers keep their full-height hit target while showing a short grip only on
hover, keyboard focus or active drag.

`KoiPopover` owns its OverlayPortal and focus scope, supports Escape and outside
click, returns focus to its trigger and removes its overlay on disposal. Its
modal barrier hides background semantics; content avoids keyboard/safe-area
insets and can scroll. Menu/popover triggers expose a single name and expanded
state. System Back first dismisses the menu/popover, then navigates back.
`KoiMenu` delegates keyboard navigation, dismissal and item activation to Material.

Run behavioral tests with `flutter test` from this package. Component exploration
lives in the workspace's `examples/ui_lab` source.

Visual roles and component recipes follow [DESIGN.md](../../DESIGN.md).
AppTheme defines UI typography (14), supporting text (12), document text (16),
neutral surfaces and independent control/list metrics. Comfortable uses actual
48-pixel targets; compact is an explicit pointer/keyboard preference. Rows grow
for larger text. KoiSelectableListTile shows a directional selection marker and a separate
keyboard focus outline. Necessary input outlines remain distinct from quiet
structural dividers. Theme tests cover actual text/foreground color pairs.
KoiSearchField, KoiToolbar and KoiReadingPane provide reusable search, wrapping
actions and bounded reading layouts. They own no business sessions or routing.

`KoiWorkbenchMetrics` centralizes the 56 px rail, 4 px content inset and 16 px
content corner radius. Visible rail selection is a 32 px neutral tile; navigation
targets stay at least 48 px. Dark surfaces use neutral charcoal, reserving moss
for actions, focus and the short content-selection marker. Window context titles
and native toolbar grouping remain host-owned; the frame consumes title slots.

## Standard widgets first

Use Flutter widgets directly: `FilledButton`, `OutlinedButton`, `TextFormField`,
`DropdownMenu`, `Checkbox`, `RadioGroup`, `Switch`, `SegmentedButton`, `TabBar`,
`DataTable`, `MenuAnchor`, `AlertDialog`, `SnackBar` and `Tooltip`. `AppTheme`
installs their shared typography, surfaces, density and state styles through
`theme/koi_material_theme.dart`; pages should not repeat those styles.

The theme also covers search, chips, banners, sheets, sliders, progress and
scrollbars. It retains Material's semantics, keyboard and platform input behavior.
Compact is a pointer preference (no ink ripple); comfortable preserves touch
feedback. Table rows have a finite expandable height to keep theme interpolation
safe. Large or unbounded cells require a deliberate host layout.

`KoiMenuItem(checked: value)` uses `CheckboxMenuButton`; the caller owns the value.
Its optional `shortcut` is a visual hint only. Register the command once in the
host's `Shortcuts/Actions`, just as with `MenuItemButton`.

The UI Lab standard catalog demonstrates six families with real form validation,
selection, sorting, menu dismissal, confirmation/cancellation, undo and sheets.
Custom Koi components remain small layout/interaction compositions where a
standard widget is insufficient; there is no parallel Koi Button/Input engine.
