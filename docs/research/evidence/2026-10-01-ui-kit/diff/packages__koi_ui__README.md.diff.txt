--- packages/koi_ui/README.md (turn baseline)
+++ packages/koi_ui/README.md
@@ -75,3 +75,26 @@
 targets stay at least 48 px. Dark surfaces use neutral charcoal, reserving moss
 for actions, focus and the short content-selection marker. Window context titles
 and native toolbar grouping remain host-owned; the frame consumes title slots.
+
+## Standard widgets first
+
+Use Flutter widgets directly: `FilledButton`, `OutlinedButton`, `TextFormField`,
+`DropdownMenu`, `Checkbox`, `RadioGroup`, `Switch`, `SegmentedButton`, `TabBar`,
+`DataTable`, `MenuAnchor`, `AlertDialog`, `SnackBar` and `Tooltip`. `AppTheme`
+installs their shared typography, surfaces, density and state styles through
+`theme/koi_material_theme.dart`; pages should not repeat those styles.
+
+The theme also covers search, chips, banners, sheets, sliders, progress and
+scrollbars. It retains Material's semantics, keyboard and platform input behavior.
+Compact is a pointer preference (no ink ripple); comfortable preserves touch
+feedback. Table rows have a finite expandable height to keep theme interpolation
+safe. Large or unbounded cells require a deliberate host layout.
+
+`KoiMenuItem(checked: value)` uses `CheckboxMenuButton`; the caller owns the value.
+Its optional `shortcut` is a visual hint only. Register the command once in the
+host's `Shortcuts/Actions`, just as with `MenuItemButton`.
+
+The UI Lab standard catalog demonstrates six families with real form validation,
+selection, sorting, menu dismissal, confirmation/cancellation, undo and sheets.
+Custom Koi components remain small layout/interaction compositions where a
+standard widget is insufficient; there is no parallel Koi Button/Input engine.
