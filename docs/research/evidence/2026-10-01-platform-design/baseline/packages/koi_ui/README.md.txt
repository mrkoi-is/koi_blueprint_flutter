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
Scaffold drawers. Pass stable external controllers to body widgets; the shell
may reparent presentation when changing layouts. `KoiResizableSplitView` needs
bounded width and height; its divider supports drag, Tab, arrows, Home and End.
`primaryOnTrailing` enables right-pane sizing. The frame exposes
`sidebarWidth/onSidebarWidthChanged` and `detailWidth/onDetailWidthChanged` so
hosts can persist both panel widths.

The title bar and fixed icon rail share `KoiThemeTokens.chromeBackground`.
The content sidebar, main body and inline details share `contentBackground`
inside one clipped, rounded surface with a small outer inset. Narrow content
drawers use the same content background. Both light and dark themes provide
distinct surfaces; ordinary Material hosts fall back to their ColorScheme.
Structural edges use a subtle color independent of control outlines. Split
dividers keep their full-height hit target while showing a short grip only on
hover, keyboard focus or active drag.

`KoiPopover` owns its OverlayPortal and focus scope, supports Escape and outside
click, returns focus to its trigger and removes its overlay on disposal.
`KoiMenu` delegates keyboard navigation, dismissal and item activation to Material.

Run behavioral tests with `flutter test` from this package. Component exploration
lives in the workspace's `examples/ui_lab` source.

Visual roles and component recipes follow [DESIGN.md](../../DESIGN.md).
AppTheme defines UI typography (14), supporting text (12), document text (16),
neutral surfaces and independent control/list metrics. Comfortable uses actual
48-pixel targets; compact is an explicit pointer/keyboard preference. Rows grow
for larger text. KoiSelectableListTile shows a separate keyboard focus outline.
KoiSearchField, KoiToolbar and KoiReadingPane provide reusable search, wrapping
actions and bounded reading layouts. They own no business sessions or routing.
