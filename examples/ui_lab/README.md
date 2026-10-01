# UI Lab

A maintenance example consuming the real `koi_ui` package. Toggle light/dark,
comfortable/compact density, 200% type, long Chinese and 320/600/1024/1440 logical
width presets. The displayed width is capped by the actual window width.

Tabs exercise components, loading/empty/error states, and adaptive layout. Use
mouse hover, Tab, Enter/Space, Escape and the resizable divider to inspect actual
interactions. The text controller remains owned by the Lab across layout changes.

This example is tested workspace source rather than an active dependency of
projects created by the blueprint generator.

The “标准组件” catalog has six sections: actions, inputs, selection, navigation,
data and feedback. Widgets consume AppTheme without local visual overrides.
Exercise form validation, dropdown selection, radio/checkbox/switch state, tab
navigation, table selection/sorting, menus, dialog cancel/confirm, snackbar undo,
banner dismissal and bottom-sheet selection. Theme/layout switches preserve the
catalog's state. The table scrolls horizontally in narrow containers.

Run directly from this directory (Flutter 3.47.2):

```sh
../../tool/flutterw run -d chrome
../../tool/flutterw build web --release
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

The small Web runner is for the maintenance catalog. No generated application
or copied package is required to preview the current source.
