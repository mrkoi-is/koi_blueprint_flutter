--- before/packages/koi_ui/README.md
+++ after/packages/koi_ui/README.md
@@ -42,9 +42,9 @@
 Navigator: a route must not hide the rail or adjacent panes from accessibility.
 
 The title bar and fixed icon rail share `KoiThemeTokens.chromeBackground`.
-The content sidebar, main body and inline details share `contentBackground`
-inside one clipped, rounded surface with a small outer inset. Narrow content
-drawers use the same content background. Both light and dark themes provide
+The resource sidebar and inspector use `panelBackground`; the main body uses
+`contentBackground`. All stay inside one clipped, rounded container with a small
+outer inset. Narrow supporting-panel drawers also use `panelBackground`. Both light and dark themes provide
 distinct surfaces; ordinary Material hosts fall back to their ColorScheme.
 Structural edges use a subtle color independent of control outlines. Split
 dividers keep their full-height hit target while showing a short grip only on
