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

Run directly from this directory (Flutter 3.50.1):

```sh
../../tool/flutterw run -d chrome
../../tool/flutterw build web --release
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

The small Web runner is for the maintenance catalog. No generated application
or copied package is required to preview the current source.

## AI test loop: rename a workspace

This is local catalog state, not a persistence/backend test. The normal main
entrypoint is unchanged. For an Agent session, enable the pinned Dart MCP's
`flutter_app_lifecycle` tools and launch `test_driver/ai_main.dart` on `chrome`.
This explicit debug entrypoint enables Flutter Driver before mounting the real
App. Use `tools/list` first; no global Agent configuration is required by the App.

1. `launch_app` with this directory's file URI, `device: chrome`, and
   `target: test_driver/ai_main.dart`. Record the returned PID.
2. Discover/connect the launch's DTD with `dtd`, then record its exact appUri.
   Pass appUri on every subsequent command; do not select another running App.
3. Read `widget_inspector/get_widget_tree`. Tap 标准组件, then 反馈, then
   重命名工作区 using the observed tree. Read the new tree for the dialog.
4. Tap the unique `ByValueKey` `catalog-rename` (`keyValueType: String`), enter
   `  AI 闭环工作区  `, then tap 确认重命名. Read back
   `当前工作区：AI 闭环工作区；排序：最近更新` with `get_text`.
5. Reopen the dialog and read its descendant EditableText. It must contain
   `AI 闭环工作区`. Change it, cancel, and read back the unchanged committed
   value. Save raw tool requests/responses, trees and a screenshot.
6. Read runtime errors and stop only the PID returned by this launch. Replay
   the fixed tests below from a fresh App instance.

All actions use `flutter_driver_command`, a bounded timeout and exact unique
finders. A missing/ambiguous target is a failure, not a reason to select first.
The 2026-11-08 local run used Dart MCP 1.2.2 + Flutter 3.47.2. Its default Web
screenshot failed because the driver PNG enum index is 4 but Web dart:ui uses 3.
On this exact Web SDK, passing `format: "3"` returned a valid PNG. Preserve the
original failure and verify the PNG; do not apply this numeric workaround on
native platforms or assume it holds for a future SDK. No SDK files were patched.

Replay from the workspace root (Python >=3.11; Windows: `py -3`):

```sh
python3 blueprint.py test --member examples/ui_lab --path test/ai_rename_journey_test.dart
python3 blueprint.py test --member examples/ui_lab --path test/browser/ai_rename_journey_test.dart --platform chrome
python3 blueprint.py validate
```

Both wrappers run the same contract in `test/support/rename_journey.dart`:
commit/trim, navigation retention, reopen/readback, empty-name validation and
cancel. The Chrome wrapper is also discovered by the existing browser gate.
For a controlled effectiveness check, temporarily remove `.trim()` from the
rename dialog's Navigator result, run the regression (must fail), restore the
exact source and rerun (must pass). Do not update the expected value to accept
the injected bug. This is a distinct mutation experiment, not a flaky retry.
