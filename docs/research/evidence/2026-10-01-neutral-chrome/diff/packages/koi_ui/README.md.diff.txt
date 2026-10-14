--- before/packages/koi_ui/README.md
+++ after/packages/koi_ui/README.md
@@ -69,3 +69,9 @@
 structural dividers. Theme tests cover actual text/foreground color pairs.
 KoiSearchField, KoiToolbar and KoiReadingPane provide reusable search, wrapping
 actions and bounded reading layouts. They own no business sessions or routing.
+
+`KoiWorkbenchMetrics` centralizes the 56 px rail, 4 px content inset and 16 px
+content corner radius. Visible rail selection is a 32 px neutral tile; navigation
+targets stay at least 48 px. Dark surfaces use neutral charcoal, reserving moss
+for actions, focus and the short content-selection marker. Window context titles
+and native toolbar grouping remain host-owned; the frame consumes title slots.
